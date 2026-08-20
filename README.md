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
