# PDF阅读

基于 Flutter 的 PDF 阅读器，使用 `pdfrx`（PDFium）渲染文档。

## 功能

- 打开本地 PDF，并保存到应用文库
- 打开网络 PDF 链接
- 最近阅读记录，自动记住页码
- 缩放、页码跳转、纵向 / 横向阅读
- 文本搜索、目录、缩略图
- 夜间模式、加密文档密码输入
- 支持 Android、iOS、macOS、Windows、Linux、Web

## 运行

```bash
cd /Users/nathan/StudioProjects/pdf_reader
flutter pub get
flutter run
```

指定设备：

```bash
flutter devices
flutter run -d macos
flutter run -d chrome
```

Windows 构建需要先开启 [开发人员模式](https://learn.microsoft.com/windows/apps/get-started/enable-your-device-for-development)，因为 `pdfrx` 依赖符号链接。

## 打包到 output/

发行包统一输出到项目根目录 `output/<版本号>/`，该目录已加入 `.gitignore`，不会提交到 Git。

```bash
chmod +x scripts/build_release.sh
./scripts/build_release.sh
```

指定平台：

```bash
./scripts/build_release.sh android macos web
./scripts/build_release.sh ios
```

只收集已有构建产物、不重新编译：

```bash
./scripts/build_release.sh --copy-only macos web
```

目录示例：

```
output/1.0.0+1/
  android/pdf_reader-1.0.0-1.apk
  android/pdf_reader-1.0.0-1.aab
  ios/pdf_reader-1.0.0-1.ipa
  macos/PDFReader.app
  macos/PDFReader-1.0.0-1.zip
  web/
```
