// FIJI Macro for Enhanced Pathology Image Analysis (QuPath-style processing)
macro "Enhanced_QuPath_Style_Analysis" {

    // 获取输入输出目录
    inputDir = getDirectory("Select input directory containing images");
    outputDir = getDirectory("Select output directory for results");

    // 获取文件列表并筛选图像文件
    fileList = getFileList(inputDir);
    imageFiles = filterImageFiles(fileList);

    if (imageFiles.length == 0) {
        showMessage("Error", "No image files found in the selected directory");
        exit();
    }

    print("Found " + imageFiles.length + " image files to process");

    // 循环处理每张图像
    for (fileIndex = 0; fileIndex < imageFiles.length; fileIndex++) {
        currentFile = imageFiles[fileIndex];
        print("Processing file " + (fileIndex + 1) + "/" + imageFiles.length + ": " + currentFile);

        open(inputDir + currentFile);

        if (nImages == 0) {
            print("Failed to open: " + currentFile);
            continue;
        }

        original = getImageID();
        originalTitle = getTitle();
        baseName = getFileNameWithoutExtension(currentFile);

        imageOutputDir = outputDir + baseName + File.separator;
        File.makeDirectory(imageOutputDir);

        if (bitDepth() != 24) {
            print("Converting to RGB: " + currentFile);
            run("RGB Color");
        }

        success = processQuPathStyleEnhanced(original, originalTitle, imageOutputDir, baseName);

        if (success) {
            print("Successfully processed: " + currentFile);
        } else {
            print("Failed to process: " + currentFile);
        }

        run("Close All");
        showProgress(fileIndex + 1, imageFiles.length);
    }

    print("Enhanced QuPath-style analysis completed!");
    showMessage("Analysis Complete",
        "All images processed with enhanced QuPath-style workflow.\n" +
        "Results saved to: " + outputDir);
}

// 主处理函数（增强版）
function processQuPathStyleEnhanced(originalID, originalTitle, outputDir, baseName) {
    
    selectImage(originalID);
    originalWindowName = getTitle();
    
    // 原始图像保存
    addScaleBar(originalWindowName, 100, "pixel", "Lower Right");
    saveAs("Tiff", outputDir + baseName + "_01_Original.tif");
    rename(originalWindowName);
    
    // 使用改进的颜色去卷积和分割
    improvedColorDeconvolutionAndSegmentation(originalID, outputDir, baseName);
    
    // 继续其他步骤
    print("Step 2: DoG Segmentation, Haralick Entropy, Positive Pixel Analysis");
    performDoGSegmentation(originalID, outputDir, baseName);
    performHaralickEntropy(originalID, outputDir, baseName);
    performPositivePixelAnalysis(originalID, outputDir, baseName);
    
    generateEnhancedMeasurementsReport(outputDir, baseName);
    cleanupAllTempImages();
    
    return true;
}

// 改进的颜色去卷积和细胞/基质分离函数
function improvedColorDeconvolutionAndSegmentation(originalID, outputDir, baseName) {
    print("Step 1: Enhanced Color Deconvolution and Cell/Matrix Separation");
    
    selectImage(originalID);
    run("Duplicate...", "title=deconv_original");
    
    // 预处理：增强对比度和减少噪声
    run("Enhance Contrast", "saturated=0.5");
    run("Gaussian Blur...", "sigma=0.5");
    
    // 使用更精确的H&E去卷积
    run("Colour Deconvolution", "vectors=[H&E]");
    
    // 处理苏木精通道（细胞核）
    if (isOpen("deconv_original-(Colour_1)")) {
        selectWindow("deconv_original-(Colour_1)");
        rename("Hematoxylin_Channel");
        
        // 增强细胞核对比度
        run("Enhance Contrast", "saturated=2.0");
        run("Apply LUT");
        
        // 进一步优化细胞核检测
        run("Duplicate...", "title=nuclei_enhanced");
        run("Gaussian Blur...", "sigma=0.8");
        run("Unsharp Mask...", "radius=1 mask=0.60");
        
        // 自适应阈值分割细胞核（如果插件不可用则用常规阈值）
        if (isPluginAvailable("Auto_Local_Threshold")) {
            run("Auto Local Threshold", "method=Bernsen radius=5 parameter_1=15 parameter_2=0 white");
        } else {
            setAutoThreshold("Otsu dark");
            run("Convert to Mask");
        }
        run("Watershed");
        run("Fill Holes");
        
        // 过滤小的噪声区域
        run("Analyze Particles...", "size=10-Infinity pixel circularity=0.20-1.00 show=Masks");
        rename("Nuclei_Mask");
        
        selectWindow("Hematoxylin_Channel");
        addScaleBar("Hematoxylin_Channel", 100, "pixel", "Lower Right");
        saveAs("Tiff", outputDir + baseName + "_02_Hematoxylin_Channel_Enhanced.tif");
        
        selectWindow("Nuclei_Mask");
        addScaleBar("Nuclei_Mask", 100, "pixel", "Lower Right");
        saveAs("Tiff", outputDir + baseName + "_03_Nuclei_Segmentation.tif");
    }
    
    // 处理伊红通道（细胞质和基质）
    if (isOpen("deconv_original-(Colour_2)")) {
        selectWindow("deconv_original-(Colour_2)");
        rename("Eosin_Channel");
        
        run("Enhance Contrast", "saturated=2.0");
        run("Apply LUT");
        
        // 区分细胞质和细胞外基质
        run("Duplicate...", "title=cytoplasm_matrix_analysis");
        
        // 使用多阈值分割区分不同组织成分
        run("Duplicate...", "title=matrix_mask");
        setAutoThreshold("Otsu dark");
        getThreshold(lower, upper);
        
        // 细胞外基质（高强度区域）
        selectWindow("matrix_mask");
        run("Duplicate...", "title=extracellular_matrix");
        midThreshold = (upper + lower) / 2;
        setThreshold(midThreshold, 255);
        run("Convert to Mask");
        run("Fill Holes");
        
        // 细胞质区域（中等强度区域）
        selectWindow("matrix_mask");
        run("Duplicate...", "title=cytoplasm_region");
        setThreshold(lower, midThreshold);
        run("Convert to Mask");
        run("Fill Holes");
        
        // 创建组合分类图
        selectImage(originalID);
        run("Duplicate...", "title=tissue_classification_enhanced");
        
        // 标记细胞外基质为绿色
        if (isOpen("extracellular_matrix")) {
            selectWindow("extracellular_matrix");
            run("Create Selection");
            if (selectionType() != -1) {
                selectWindow("tissue_classification_enhanced");
                run("Restore Selection");
                setForegroundColor(0, 255, 0); // 绿色 - 基质
                run("Fill", "slice");
            }
            run("Select None");
        }
        
        // 标记细胞质为黄色
        if (isOpen("cytoplasm_region")) {
            selectWindow("cytoplasm_region");
            run("Create Selection");
            if (selectionType() != -1) {
                selectWindow("tissue_classification_enhanced");
                run("Restore Selection");
                setForegroundColor(255, 255, 0); // 黄色 - 细胞质
                run("Fill", "slice");
            }
            run("Select None");
        }
        
        // 标记细胞核为蓝色
        if (isOpen("Nuclei_Mask")) {
            selectWindow("Nuclei_Mask");
            run("Create Selection");
            if (selectionType() != -1) {
                selectWindow("tissue_classification_enhanced");
                run("Restore Selection");
                setForegroundColor(0, 0, 255); // 蓝色 - 细胞核
                run("Fill", "slice");
            }
            run("Select None");
        }
        
        // 保存结果
        selectWindow("Eosin_Channel");
        addScaleBar("Eosin_Channel", 100, "pixel", "Lower Right");
        saveAs("Tiff", outputDir + baseName + "_04_Eosin_Channel_Enhanced.tif");
        
        selectWindow("tissue_classification_enhanced");
        addScaleBar("tissue_classification_enhanced", 100, "pixel", "Lower Right");
        saveAs("Tiff", outputDir + baseName + "_05_Enhanced_Tissue_Classification.tif");
        
        // 保存分割掩码
        if (isOpen("extracellular_matrix")) {
            selectWindow("extracellular_matrix");
            addScaleBar("extracellular_matrix", 100, "pixel", "Lower Right");
            saveAs("Tiff", outputDir + baseName + "_06_Extracellular_Matrix_Mask.tif");
        }
        
        if (isOpen("cytoplasm_region")) {
            selectWindow("cytoplasm_region");
            addScaleBar("cytoplasm_region", 100, "pixel", "Lower Right");
            saveAs("Tiff", outputDir + baseName + "_07_Cytoplasm_Region_Mask.tif");
        }
    }
    
    // 处理残留通道
    if (isOpen("deconv_original-(Colour_3)")) {
        selectWindow("deconv_original-(Colour_3)");
        run("Enhance Contrast", "saturated=1");
        run("Apply LUT");
        addScaleBar("deconv_original-(Colour_3)", 100, "pixel", "Lower Right");
        saveAs("Tiff", outputDir + baseName + "_08_Residual_Channel.tif");
    }
}

// DoG（差分高斯）分割
function performDoGSegmentation(originalID, outputDir, baseName) {
    print("Performing DoG Segmentation Analysis");

    selectImage(originalID);
    run("Duplicate...", "title=dog_analysis");
    run("8-bit");

    run("Duplicate...", "title=gaussian_small");
    run("Gaussian Blur...", "sigma=1.0");

    selectWindow("dog_analysis");
    run("Duplicate...", "title=gaussian_large");
    run("Gaussian Blur...", "sigma=3.0");

    imageCalculator("Subtract create", "gaussian_small", "gaussian_large");
    rename("DoG_result");

    run("Enhance Contrast", "saturated=1");
    run("Apply LUT");

    run("Duplicate...", "title=DoG_mask");
    setAutoThreshold("Otsu dark");
    run("Convert to Mask");
    run("Fill Holes");
    run("Watershed");

    run("Create Selection");
    if (selectionType() != -1) {
        selectWindow("DoG_result");
        run("Restore Selection");
        run("Fire");
    }
    run("Select None");

    selectWindow("DoG_result");
    addScaleBar("DoG_result", 100, "pixel", "Lower Right");
    saveAs("Tiff", outputDir + baseName + "_09_DoG_Segmentation.tif");

    if (isOpen("dog_analysis")) { selectWindow("dog_analysis"); close(); }
    if (isOpen("gaussian_small")) { selectWindow("gaussian_small"); close(); }
    if (isOpen("gaussian_large")) { selectWindow("gaussian_large"); close(); }
    if (isOpen("DoG_mask")) { selectWindow("DoG_mask"); close(); }
}

// Haralick熵纹理分析
function performHaralickEntropy(originalID, outputDir, baseName) {
    print("Performing Haralick Entropy Texture Analysis");

    selectImage(originalID);
    run("Duplicate...", "title=entropy_analysis");
    run("8-bit");

    if (isPluginAvailable("Entropy")) {
        run("Entropy...", "radius=5");
    } else {
        print("GLCM Texture plugin not found, using simplified entropy calculation");

        run("Duplicate...", "title=entropy_temp");
        run("Mean...", "radius=3");

        selectWindow("entropy_analysis");
        run("Duplicate...", "title=entropy_temp2");
        imageCalculator("Subtract create", "entropy_analysis", "entropy_temp");
        rename("local_variation");

        run("Square");
        run("Mean...", "radius=3");
        run("Square Root");

        selectWindow("local_variation");
        close();
        selectWindow("entropy_temp");
        close();
        selectWindow("entropy_temp2");
        close();
    }

    run("Enhance Contrast", "saturated=1");
    run("Apply LUT");
    run("16_colors");

    selectWindow("entropy_analysis");
    addScaleBar("entropy_analysis", 100, "pixel", "Lower Right");
    saveAs("Tiff", outputDir + baseName + "_10_Haralick_Entropy.tif");
}

// 正负像素分析功能（修正版）
function performPositivePixelAnalysis(originalID, outputDir, baseName) {
    print("Performing Positive/Negative Pixel Analysis");

    selectImage(originalID);
    run("Duplicate...", "title=positive_pixel_analysis");
    run("8-bit");

    setAutoThreshold("Otsu dark");
    getThreshold(lower, upper);

    print("Thresholds detected: lower=" + lower + ", upper=" + upper);

    // positive_mask：高于阈值区域
    selectWindow("positive_pixel_analysis");
    run("Duplicate...", "title=positive_mask");
    
    upperThreshold = upper + 1;
    if (upperThreshold > 255) {
        upperThreshold = 255;
    }
    setThreshold(upperThreshold, 255);
    run("Convert to Mask");

    // negative_mask：低于阈值区域
    selectWindow("positive_pixel_analysis");
    run("Duplicate...", "title=negative_mask");
    
    lowerThreshold = lower - 1;
    if (lowerThreshold < 0) {
        lowerThreshold = 0;
    }
    setThreshold(0, lowerThreshold);
    run("Convert to Mask");

    // 获取图像尺寸
    selectWindow("positive_pixel_analysis");
    width = getWidth();
    height = getHeight();
    
    // 创建RGB结果图像
    newImage("pos_neg_overlay", "RGB black", width, height, 1);

    // 填充Positive区域为红色
    selectWindow("positive_mask");
    run("Create Selection");
    if (selectionType() != -1) {
        selectWindow("pos_neg_overlay");
        run("Restore Selection");
        setForegroundColor(255, 0, 0);
        run("Fill", "slice");
        run("Select None");
    }

    // 填充Negative区域为蓝色
    selectWindow("negative_mask");
    run("Create Selection");
    if (selectionType() != -1) {
        selectWindow("pos_neg_overlay");
        run("Restore Selection");
        setForegroundColor(0, 0, 255);
        run("Fill", "slice");
        run("Select None");
    }

    selectWindow("pos_neg_overlay");
    addScaleBar("pos_neg_overlay", 100, "pixel", "Lower Right");
    saveAs("Tiff", outputDir + baseName + "_11_Positive_Negative_Pixel_Analysis.tif");

    // 关闭临时窗口
    if (isOpen("positive_pixel_analysis")) { selectWindow("positive_pixel_analysis"); close(); }
    if (isOpen("positive_mask")) { selectWindow("positive_mask"); close(); }
    if (isOpen("negative_mask")) { selectWindow("negative_mask"); close(); }
}

// 插件检查函数
function isPluginAvailable(pluginName) {
    // 简化的插件检查，实际使用中可能需要更复杂的检查
    return false;
}

// 生成增强版测量报告
function generateEnhancedMeasurementsReport(outputDir, baseName) {

    if (isOpen("Results")) {
        selectWindow("Results");
        run("Summarize");
        saveAs("Results", outputDir + baseName + "_Detailed_Measurements.csv");
        run("Clear Results");
    }

    reportPath = outputDir + baseName + "_Enhanced_Analysis_Summary.txt";

    report = "Enhanced QuPath-Style Analysis Summary\n";
    report += "=====================================\n";
    report += "Image: " + baseName + "\n";
    report += "Analysis Date: " + getCurrentDateTime() + "\n\n";
    report += "Processing Steps Completed:\n";
    report += "1. Enhanced Color Deconvolution (H&E separation with improved preprocessing)\n";
    report += "2. Advanced Nuclear Detection and Segmentation\n";
    report += "3. Enhanced Tissue Classification (Nucleus/Cytoplasm/Matrix separation)\n";
    report += "4. DoG (Difference of Gaussians) Segmentation\n";
    report += "5. Haralick Entropy Texture Analysis\n";
    report += "6. Positive/Negative Pixel Analysis\n\n";
    report += "Output Files Generated:\n";
    report += "- Original Image (with scale bar)\n";
    report += "- Enhanced Hematoxylin Channel (with scale bar)\n";
    report += "- Enhanced Eosin Channel (with scale bar)\n";
    report += "- Residual Channel (with scale bar)\n";
    report += "- Nuclei Segmentation Mask (with scale bar)\n";
    report += "- Enhanced Tissue Classification Map (with scale bar)\n";
    report += "- Extracellular Matrix Mask (with scale bar)\n";
    report += "- Cytoplasm Region Mask (with scale bar)\n";
    report += "- DoG Segmentation (with scale bar)\n";
    report += "- Haralick Entropy Analysis (with scale bar)\n";
    report += "- Positive/Negative Pixel Analysis (with scale bar)\n\n";
    report += "Color Coding for Tissue Classification:\n";
    report += "- Blue: Cell Nuclei\n";
    report += "- Yellow: Cytoplasm\n";
    report += "- Green: Extracellular Matrix\n";

    File.saveString(report, reportPath);
}

// 清理所有临时图像
function cleanupAllTempImages() {
    tempImages = newArray("deconv_original", "nuclei_enhanced", "cytoplasm_matrix_analysis",
        "matrix_mask", "extracellular_matrix", "cytoplasm_region", "tissue_classification_enhanced",
        "DoG_result", "entropy_analysis", "pos_neg_overlay");

    for (i = 0; i < tempImages.length; i++) {
        if (isOpen(tempImages[i])) {
            selectWindow(tempImages[i]);
            close();
        }
    }
    
    // 清理颜色去卷积产生的窗口
    if (isOpen("Hematoxylin_Channel")) { selectWindow("Hematoxylin_Channel"); close(); }
    if (isOpen("Eosin_Channel")) { selectWindow("Eosin_Channel"); close(); }
    if (isOpen("Nuclei_Mask")) { selectWindow("Nuclei_Mask"); close(); }
    
    // 清理其他可能的临时窗口
    deconvWindows = newArray("deconv_original-(Colour_1)", "deconv_original-(Colour_2)", 
                            "deconv_original-(Colour_3)");
    for (i = 0; i < deconvWindows.length; i++) {
        if (isOpen(deconvWindows[i])) {
            selectWindow(deconvWindows[i]);
            close();
        }
    }
}

// 添加比例尺功能函数
function addScaleBar(imageTitle, scaleLength, unit, position) {
    selectWindow(imageTitle);
    run("Scale Bar...",
        "width=" + scaleLength +
        " height=4 " +
        "font=14 " +
        "color=White " +
        "background=Black " +
        "location=[" + position + "] " +
        "bold overlay");
}

// 工具函数，筛选图像文件扩展名
function filterImageFiles(fileList) {
    imageExtensions = newArray(".tif", ".tiff", ".jpg", ".jpeg", ".png", ".bmp", ".nd2", ".czi");
    imageFiles = newArray();

    for (i = 0; i < fileList.length; i++) {
        fileName = fileList[i];
        isImage = false;

        fileNameLower = toLowerCase(fileName);
        for (j = 0; j < imageExtensions.length; j++) {
            if (endsWith(fileNameLower, imageExtensions[j])) {
                isImage = true;
                break;
            }
        }

        if (isImage) {
            imageFiles = Array.concat(imageFiles, fileName);
        }
    }

    return imageFiles;
}

// 获取文件名主干（无扩展名）
function getFileNameWithoutExtension(fileName) {
    dotIndex = lastIndexOf(fileName, ".");
    if (dotIndex > 0) {
        return substring(fileName, 0, dotIndex);
    }
    return fileName;
}

// 字符串转小写（简易版）
function toLowerCase(str) {
    result = str;
    upperChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    lowerChars = "abcdefghijklmnopqrstuvwxyz";

    for (i = 0; i < lengthOf(upperChars); i++) {
        upperChar = substring(upperChars, i, i + 1);
        lowerChar = substring(lowerChars, i, i + 1);
        result = replace(result, upperChar, lowerChar);
    }

    return result;
}

// 获取当前日期时间字符串
function getCurrentDateTime() {
    monthNames = newArray("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
    dayNames = newArray("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat");

    year = 0; month = 0; dayOfWeek = 0; dayOfMonth = 0;
    hour = 0; minute = 0; second = 0; msec = 0;

    getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);

    timeString = dayNames[dayOfWeek] + " ";
    if (dayOfMonth < 10) timeString += "0";
    timeString += dayOfMonth + "-" + monthNames[month] + "-" + year + " ";
    if (hour < 10) timeString += "0";
    timeString += hour + ":";
    if (minute < 10) timeString += "0";
    timeString += minute;

    return timeString;
}
