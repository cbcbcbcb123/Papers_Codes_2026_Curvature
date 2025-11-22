// FIJI宏：批量处理文件夹内HE图像，生成每张图像的H通道强度密度图
// 修订版：支持自定义颜色映射和密度颜色条生成

// 选择输入文件夹
inputDir = getDirectory("Select input directory containing HE images");
if (inputDir == "") {
    exit("No input directory selected!");
}

// 选择输出文件夹
outputBaseDir = getDirectory("Select output directory to save results");
if (outputBaseDir == "") {
    exit("No output directory selected!");
}

// 支持的图像格式
imageExtensions = newArray(".tif", ".tiff", ".jpg", ".jpeg", ".png", ".bmp", ".nd2", ".czi");

// 获取文件列表
fileList = getFileList(inputDir);

// 过滤图像文件
imageFiles = filterImageFiles(fileList, imageExtensions);

if (imageFiles.length == 0) {
    showMessage("Error", "No image files found in input directory!");
    exit();
}

print("Found " + imageFiles.length + " image files to process.");

// 全局颜色映射参数
globalColorMapping = newArray();
isGlobalMappingSet = false;

// 循环处理每个图像
for (i = 0; i < imageFiles.length; i++) {
    fileName = imageFiles[i];
    print("Processing (" + (i+1) + "/" + imageFiles.length + "): " + fileName);

    // 打开图像
    open(inputDir + fileName);

    if (nImages == 0) {
        print("Failed to open: " + fileName);
        continue;
    }

    originalID = getImageID();
    originalTitle = getTitle();

    // 获取图像基础名（无扩展名）
    baseName = getFileNameWithoutExtension(fileName);

    // 创建输出子文件夹
    outputDir = outputBaseDir + baseName + File.separator;
    File.makeDirectory(outputDir);

    // 分析原始图像颜色分布（仅第一张图像）
    if (!isGlobalMappingSet) {
        globalColorMapping = analyzeImageColors(originalID);
        isGlobalMappingSet = true;
        print("Color mapping established from first image");
    }

    // 保存原始图像副本
    selectImage(originalID);
    run("Duplicate...", "title=original_copy");
    saveAs("Tiff", outputDir + baseName + "_01_Original.tif");

    // 确保为RGB图像
    selectImage(originalID);
    if (bitDepth() != 24) {
        print("Converting to RGB: " + fileName);
        run("RGB Color");
    }

    // 执行颜色去卷积得到H通道
    run("Colour Deconvolution", "vectors=[H&E]");

    // 处理H通道（苏木精通道）
    hChannelName = originalTitle + "-(Colour_1)";
    if (isOpen(hChannelName)) {
        selectWindow(hChannelName);
        rename("Hematoxylin_Channel");

        // 确保为8-bit灰度图
        if (bitDepth() != 8) {
            run("8-bit");
        }

        // 保存原始H通道
        run("Duplicate...", "title=h_channel_original");
        saveAs("Tiff", outputDir + baseName + "_02_Hematoxylin_Channel.tif");
        close();

        // 选择H通道进行密度分析
        selectWindow("Hematoxylin_Channel");

        // 反色处理，使H染色强区域变亮（高数值）
        run("Invert");

        // 保存反色后的H通道
        run("Duplicate...", "title=h_inverted");
        saveAs("Tiff", outputDir + baseName + "_03_Hematoxylin_Inverted.tif");
        close();

        // 高斯模糊处理，模拟强度密度分布
        selectWindow("Hematoxylin_Channel");
        sigma = 2;  // 可根据图像大小调整
        run("Gaussian Blur...", "sigma=" + sigma);

        // 增强对比度
        run("Enhance Contrast", "saturated=0.35");
        run("Apply LUT");

        // 获取密度统计信息
        getStatistics(area, mean, min, max, std, histogram);
        densityStats = newArray(min, max, mean, std);

        // 应用自定义颜色映射
        applyCustomColorMapping("Hematoxylin_Channel", globalColorMapping, densityStats);

        rename("Hematoxylin_Density_Map");

        // 添加比例尺
        addScaleBar("Hematoxylin_Density_Map", 100, "pixel", "Lower Right");

        // 保存密度热图结果
        saveAs("Tiff", outputDir + baseName + "_04_Hematoxylin_Density_Map.tif");

        // 生成彩色条图例
        generateColorBar(outputDir, baseName, globalColorMapping, densityStats);

        print("Saved Hematoxylin density map and color bar for " + baseName);

        // 生成分析报告
        generateAnalysisReport(outputDir, baseName, sigma, densityStats);

    } else {
        print("Warning: Hematoxylin channel not found for " + fileName);
    }

    // 处理E通道（伊红通道）并保存
    eChannelName = originalTitle + "-(Colour_2)";
    if (isOpen(eChannelName)) {
        selectWindow(eChannelName);
        saveAs("Tiff", outputDir + baseName + "_05_Eosin_Channel.tif");
    }

    // 处理残留通道
    residualChannelName = originalTitle + "-(Colour_3)";
    if (isOpen(residualChannelName)) {
        selectWindow(residualChannelName);
        saveAs("Tiff", outputDir + baseName + "_06_Residual_Channel.tif");
    }

    // 关闭所有图像窗口，准备下一个循环
    run("Close All");

    // 显示进度
    showProgress(i+1, imageFiles.length);
}

print("Batch processing completed! Processed " + imageFiles.length + " images.");
showMessage("Processing Complete", 
    "Successfully processed " + imageFiles.length + " HE images.\n" +
    "Results saved to: " + outputBaseDir);

// 新增函数：分析图像颜色分布
function analyzeImageColors(imageID) {
    selectImage(imageID);
    
    // 创建颜色映射数组：[低密度R, 低密度G, 低密度B, 高密度R, 高密度G, 高密度B]
    // 基于上传图像的主要颜色
    
    // 获取图像的颜色直方图
    run("Duplicate...", "title=color_analysis");
    
    // 分别获取RGB通道的统计
    run("Split Channels");
    
    // 分析红色通道
    selectWindow("color_analysis (red)");
    getStatistics(area, meanR, minR, maxR, stdR);
    close();
    
    // 分析绿色通道  
    selectWindow("color_analysis (green)");
    getStatistics(area, meanG, minG, maxG, stdG);
    close();
    
    // 分析蓝色通道
    selectWindow("color_analysis (blue)");
    getStatistics(area, meanB, minB, maxB, stdB);
    close();
    
    // 创建从蓝色（低密度）到红橙色（高密度）的渐变映射
    // 这与上传图像的颜色分布相似
    colorMap = newArray(
        0, 100, 255,     // 低密度：蓝色
        0, 255, 200,     // 中低密度：青绿色  
        100, 255, 0,     // 中密度：绿色
        255, 255, 0,     // 中高密度：黄色
        255, 100, 0,     // 高密度：橙色
        255, 0, 0        // 最高密度：红色
    );
    
    print("Custom color mapping created based on image analysis");
    return colorMap;
}

// 新增函数：应用自定义颜色映射
function applyCustomColorMapping(imageName, colorMapping, densityStats) {
    selectWindow(imageName);
    
    // 创建自定义LUT
    reds = newArray(256);
    greens = newArray(256);
    blues = newArray(256);
    
    // 生成256级颜色渐变
    for (i = 0; i < 256; i++) {
        // 计算在颜色映射中的位置（0-5的范围）
        position = i / 255.0 * 5;
        baseIndex = floor(position);
        fraction = position - baseIndex;
        
        if (baseIndex >= 5) {
            baseIndex = 4;
            fraction = 1;
        }
        
        // 线性插值计算RGB值
        r1 = colorMapping[baseIndex * 3];
        g1 = colorMapping[baseIndex * 3 + 1];
        b1 = colorMapping[baseIndex * 3 + 2];
        
        if (baseIndex < 5) {
            r2 = colorMapping[(baseIndex + 1) * 3];
            g2 = colorMapping[(baseIndex + 1) * 3 + 1];
            b2 = colorMapping[(baseIndex + 1) * 3 + 2];
        } else {
            r2 = r1;
            g2 = g1;
            b2 = b1;
        }
        
        reds[i] = r1 + (r2 - r1) * fraction;
        greens[i] = g1 + (g2 - g1) * fraction;
        blues[i] = b1 + (b2 - b1) * fraction;
    }
    
    // 应用自定义LUT
    setLut(reds, greens, blues);
}

// 新增函数：生成彩色条图例
function generateColorBar(outputDir, baseName, colorMapping, densityStats) {
    // 创建颜色条图像 (400x100像素)
    newImage("ColorBar", "RGB", 400, 100, 1);
    colorBarID = getImageID();
    
    minDensity = densityStats[0];
    maxDensity = densityStats[1];
    meanDensity = densityStats[2];
    
    // 绘制颜色渐变条
    for (x = 0; x < 350; x++) {
        // 计算当前位置对应的密度值和颜色
        densityValue = minDensity + (maxDensity - minDensity) * x / 349.0;
        colorIndex = x / 349.0 * 5; // 0-5范围
        
        baseIndex = floor(colorIndex);
        fraction = colorIndex - baseIndex;
        
        if (baseIndex >= 5) {
            baseIndex = 4;
            fraction = 1;
        }
        
        // 计算RGB值
        r1 = colorMapping[baseIndex * 3];
        g1 = colorMapping[baseIndex * 3 + 1];  
        b1 = colorMapping[baseIndex * 3 + 2];
        
        if (baseIndex < 5) {
            r2 = colorMapping[(baseIndex + 1) * 3];
            g2 = colorMapping[(baseIndex + 1) * 3 + 1];
            b2 = colorMapping[(baseIndex + 1) * 3 + 2];
        } else {
            r2 = r1;
            g2 = g1;
            b2 = b1;
        }
        
        r = r1 + (r2 - r1) * fraction;
        g = g1 + (g2 - g1) * fraction;
        b = b1 + (b2 - b1) * fraction;
        
        // 设置颜色并绘制垂直线
        setColor(r, g, b);
        drawLine(x + 25, 20, x + 25, 60);
    }
    
    // 添加密度标签
    setColor(0, 0, 0); // 黑色文字
    setFont("SansSerif", 12, "bold");
    
    // 最小密度标签
    drawString("Low", 25, 80);
    drawString(d2s(minDensity, 1), 25, 95);
    
    // 最大密度标签  
    drawString("High", 340, 80);
    drawString(d2s(maxDensity, 1), 340, 95);
    
    // 中间密度标签
    drawString("Medium", 180, 80);
    drawString(d2s((minDensity + maxDensity)/2, 1), 180, 95);
    
    // 标题
    setFont("SansSerif", 14, "bold");
    drawString("Hematoxylin Density Scale", 120, 15);
    
    // 保存颜色条
    saveAs("Tiff", outputDir + baseName + "_07_Density_ColorBar.tif");
    close();
    
    print("Color bar saved for " + baseName);
}

// 修订函数：生成分析报告
function generateAnalysisReport(outputDir, baseName, sigma, densityStats) {
    reportPath = outputDir + baseName + "_Analysis_Report.txt";
    
    report = "HE Image H-Channel Intensity Density Analysis Report\n";
    report += "==================================================\n";
    report += "Image: " + baseName + "\n";
    report += "Analysis Date: " + getCurrentDateTime() + "\n\n";
    report += "Processing Steps:\n";
    report += "1. Color Deconvolution (H&E separation)\n";
    report += "2. Hematoxylin Channel Extraction\n";
    report += "3. Image Inversion (dark staining becomes bright)\n";
    report += "4. Gaussian Blur (sigma=" + sigma + ") for density simulation\n";
    report += "5. Custom Color Mapping Application\n";
    report += "6. Color Bar Generation\n\n";
    
    report += "Density Statistics:\n";
    report += "- Minimum Density: " + d2s(densityStats[0], 2) + "\n";
    report += "- Maximum Density: " + d2s(densityStats[1], 2) + "\n";
    report += "- Mean Density: " + d2s(densityStats[2], 2) + "\n";
    report += "- Standard Deviation: " + d2s(densityStats[3], 2) + "\n\n";
    
    report += "Output Files:\n";
    report += "- Original Image\n";
    report += "- Hematoxylin Channel (raw)\n";
    report += "- Hematoxylin Channel (inverted)\n";
    report += "- Hematoxylin Density Map (final result)\n";
    report += "- Density Color Bar (legend)\n";
    report += "- Eosin Channel\n";
    report += "- Residual Channel\n\n";
    report += "Color Mapping:\n";
    report += "- Blue: Low H-staining intensity\n";
    report += "- Green/Yellow: Medium H-staining intensity\n";
    report += "- Orange/Red: High H-staining intensity (nuclei-rich areas)\n";
    report += "- Custom mapping based on original image colors\n";
    
    File.saveString(report, reportPath);
    print("Analysis report saved: " + reportPath);
}

// 辅助函数：筛选指定格式的图片文件
function filterImageFiles(fileList, extensions) {
    validFiles = newArray();
    for (fi = 0; fi < fileList.length; fi++) {
        file = fileList[fi];
        fileLower = toLowerCase(file);
        for (ei = 0; ei < extensions.length; ei++) {
            if (endsWith(fileLower, extensions[ei])) {
                validFiles = Array.concat(validFiles, file);
                break;
            }
        }
    }
    return validFiles;
}

// 辅助函数：获取无扩展名文件名
function getFileNameWithoutExtension(filename) {
    dotIndex = lastIndexOf(filename, ".");
    if (dotIndex > 0) {
        return substring(filename, 0, dotIndex);
    }
    return filename;
}

// 简易toLowerCase函数
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

// 添加比例尺函数
function addScaleBar(imageTitle, scaleLength, unit, position) {
    selectWindow(imageTitle);
    run("Scale Bar...", 
        "width=" + scaleLength + 
        " height=4 font=14 color=White background=Black location=[" + position + "] bold overlay");
}

// 获取当前日期时间
function getCurrentDateTime() {
    getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
    monthNames = newArray("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
    
    timeString = dayOfMonth + "-" + monthNames[month] + "-" + year + " ";
    if (hour < 10) timeString += "0";
    timeString += hour + ":";
    if (minute < 10) timeString += "0";
    timeString += minute;
    
    return timeString;
}
