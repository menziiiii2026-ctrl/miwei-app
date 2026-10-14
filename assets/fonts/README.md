# Portfolio v1 字体与分发依据

本目录只保存可随 Portfolio v1 App 分发的字体。旧版来自本机字体册的九个文件缺少嵌入和分发证明，已从本发布分支的资源目录移出；发布包不得再包含它们。旧版拼贴场景存储的字体枚举 ID 保持不变，打开旧作品时由新字体替代显示。

| 场景 | 发布字体 | 文件 | 许可 |
| --- | --- | --- | --- |
| 日志年月、编辑器粗标题 | Bungee | `Bungee-Regular.ttf` | SIL OFL 1.1 |
| 日历日期 | Coming Soon | `ComingSoon-Regular.ttf` | Apache 2.0 |
| 编辑器手写 1 | Long Cang | `LongCang-Regular.ttf` | SIL OFL 1.1 |
| 编辑器手写 2 | Ma Shan Zheng | `MaShanZheng-Regular.ttf` | SIL OFL 1.1 |
| 编辑器打字机 | Courier Prime | `CourierPrime-Regular.ttf`、`CourierPrime-Bold.ttf` | SIL OFL 1.1 |
| 编辑器韩文手写 | Nanum Pen Script | `NanumPenScript-Regular.ttf` | SIL OFL 1.1 |
| 编辑器简体中文像素 | Fusion Pixel 12px Proportional zh-Hans | `fusion-pixel-12px-proportional-zh_hans.ttf` | SIL OFL 1.1 |
| 编辑器常规黑体 | iOS 系统 PingFang SC | 不复制系统字体 | 由 iOS 提供 |

Google Fonts 的六个字族取自其官方仓库 [google/fonts](https://github.com/google/fonts)，固定在提交 `bd8f81ddb5c74d5c8897b36ad88b440266245103`。每个字体对应的原始许可证复制在 `licenses/`；Google Fonts 官方仓库说明每个字族目录附有其许可文件。Fusion Pixel 取自 [作者的官方 2026.09.25 发布包](https://github.com/TakWolf/fusion-pixel-font/releases/tag/2026.09.25)，其许可证和发布包中的上游字体许可一并保存在 `licenses/`。使用这些字体时须保留对应版权声明与许可证，不可将字体文件单独作为商品出售。

字体文件 SHA-256：

```text
c4f5361ce120af3e6b9156d0bf379fa19cda2ea0cd18ac01fd99596c6bf66e3f  Bungee-Regular.ttf
cf81388f587ff6122de1a705d1070b8f00abccdba66108509908b5d10715068c  ComingSoon-Regular.ttf
ff1f38786c849d1c41fa8e447960abdb2bd75fdfb0cfcdeb524fad65a5af3638  CourierPrime-Bold.ttf
72f793376f8e2841656bf21d77a5de010f2929bd6956a22ee848ad0c7eb978af  CourierPrime-Regular.ttf
e5bf2c3f24ef2327c6f136d8f73e2f9dfdf44896fdbeb35a9515f44777bb91bc  LongCang-Regular.ttf
6d2546bb189c732a8ca29af9e22457b152387d158aa459e4ac2ce1e51788b7fb  MaShanZheng-Regular.ttf
6f0d1ab29c7894010dc88831fb7a0a51edb79136e450344183de5b1a8b52bd43  NanumPenScript-Regular.ttf
b2ee68647dc257fa697e4d0c78f9b59461bc504a023b9a3b5ad66f358bbb1613  fusion-pixel-12px-proportional-zh_hans.ttf
```

`UIAppFonts` 必须只列出本目录的八个字体文件。字体展示名称、运行时 PostScript 名和历史枚举 ID 的映射在 `CollageTextFont` 中维护；不应改动历史枚举 ID。若以后购买商业字体，请保存字体厂商的许可证正文、购买凭证和明确允许 iOS App 嵌入、TestFlight 外部测试及 GitHub 私有仓库保存源文件的授权条款，再更换资源。
