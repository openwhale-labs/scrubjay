# ScrubJay

干净地卸载 Mac 应用。

把图标从「应用程序」拖进废纸篓,不等于卸载。应用用过一段时间后,缓存、偏好设置、容器、窗口状态、日志、launch agent 会留在用户库的各个角落。ScrubJay 把应用和这些残留一起找出来、一起移进废纸篓。只进废纸篓,不做永久删除,删错了随时捞回来。

**ScrubJay 0.1 已发布**,公证过的 DMG 在 [scrubjay.openwhale.dev](https://scrubjay.openwhale.dev) 下载,也可以用 Homebrew:

```
brew install --cask openwhale-labs/tap/scrubjay
```

早期版本,会有毛边。

## 它怎么判断哪些文件属于这个应用

把一个文件归给一个应用,是这个工具的全部难点。`com.google.Chrome.plist` 显然属于 Chrome;`com.google.Chrome.beta` 呢?名字里带 Chrome 的目录呢?

ScrubJay 给每个匹配结果标一个置信级别,由置信级别决定界面敢不敢替你预选:

| 级别 | 依据 | 例子 | 默认 |
|---|---|---|---|
| certain | Bundle ID 精确匹配 | `com.google.Chrome.plist` | 预选 |
| high | Bundle ID 前缀加已知的 helper 后缀 | `com.google.Chrome.helper` | 预选 |
| medium | 应用名精确匹配 | `Google Chrome/` | 预选并标出 |
| low | 弱信号:未知后缀、渠道名、共享容器 | `com.google.Chrome.beta` | 从不预选 |

low 级别的文件永远不会被自动勾上,要删得你自己看过再勾。应用还在运行时,删除按钮是禁用的。

## 命令行

图形界面之外,同一套引擎也有 CLI:

```
$ scrubjay scan "Google Chrome"
Google Chrome (com.google.Chrome) — /Applications/Google Chrome.app

[certain]
  ~/Library/Preferences/com.google.Chrome.plist  (4 KB)

[medium]
  ~/Library/Application Support/Google/Chrome  (7.56 GB)
  ~/Library/Caches/Google/Chrome  (1.78 GB)

3 items, 9.33 GB
```

`scan` 只报告,不删任何东西。`remove` 给出同样的报告,确认后把文件移进废纸篓。`dev` 列出可以放心清掉的开发缓存(npm、pnpm、DerivedData、Homebrew 下载,清掉后用到时会重新拉取或重建)。`orphans` 找出没有任何已装应用认领的残留文件,也就是从前直接拖掉图标留下的痕迹。

## 它不做的事

不做「系统优化」,不装后台常驻(helper 只在删除需要提权时工作),不收集任何数据。

## 从源码构建

```
brew install xcodegen
xcodegen
xcodebuild -project ScrubJay.xcodeproj -scheme ScrubJay build
```

CLI 直接 `swift run scrubjay`。引擎是一个无 UI 依赖的库(`ScrubJayKit`),匹配规则是纯函数,每条规则都有单元测试。设计细节见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 要求

- macOS 14 或更新
- 从源码构建需要 Swift 6.0 工具链

## 许可

源码公开,但不是 OSI 意义上的开源:Apache 2.0 加 [Commons Clause](https://commonsclause.com/)。可以读、改、自用、再分发;不允许售卖 ScrubJay 或主要价值来自它的产品。详见 [LICENSE](LICENSE)。
