# 技术实现说明

Mi味是一款将美食照片整理成个人食记的 App。这份代码对应 TestFlight 测试版 `0.1.0 (1)` 的 Portfolio v1 快照，供招聘方查看实际实现。产品定位、交互与真机截图见[仓库首页](../README.md)。

## 架构一览

![Mi味系统架构：记录和图片先在设备内保存，再通过同步队列进入 Supabase](../diagrams/miwei-architecture.svg)

记录从拍摄或相册输入开始：用户在本机确认食物范围、选择餐盘，补充菜名和类型。App 将结构化记录写入 SwiftData，将原图、食物图和餐盘成品保存在设备文件中，同时登记待同步操作。食物展柜与饮食日志从本地记录读取；今日／本周拼贴按记录数量匹配预设模板，在设备上生成可编辑的画面。登录后，同步队列再把记录和图片送往 Supabase，用于账号恢复与换机使用。

| 层次 | 当前实现 | 从哪里看代码 |
| --- | --- | --- |
| 界面与交互 | SwiftUI：拍摄、入库、展柜、日志和拼贴编辑 | [`Features/`](../iOS/MealPlate/MealPlate/Features/)、[`AppShellView.swift`](../iOS/MealPlate/MealPlate/Features/Shell/AppShellView.swift) |
| 本机图片处理 | 修正照片方向，按用户确认的范围裁切，合成餐盘图片 | [`CaptureImageNormalizer.swift`](../iOS/MealPlate/MealPlate/Services/CaptureImageNormalizer.swift)、[`PNGComposer.swift`](../iOS/MealPlate/MealPlate/Services/PNGComposer.swift) |
| 本地数据 | SwiftData 保存菜品、品鉴记录和待同步操作；图片文件单独保存 | [`Data/`](../iOS/MealPlate/MealPlate/Data/)、[`DishLibraryService.swift`](../iOS/MealPlate/MealPlate/Services/DishLibraryService.swift) |
| 模板拼贴 | 按记录数量选择预设模板，保存可编辑场景与预览 | [`CollageGeneration/`](../iOS/MealPlate/MealPlate/Services/CollageGeneration/)、[`CollageEditor/`](../iOS/MealPlate/MealPlate/Features/Journal/CollageEditor/)、[`app-contract/`](../app-contract/) |
| 云端同步 | 本地先保存，队列重试；Supabase 提供账号、PostgreSQL 和图片存储 | [`CloudSyncCoordinator.swift`](../iOS/MealPlate/MealPlate/Cloud/CloudSyncCoordinator.swift)、[`SupabaseCloudStore.swift`](../iOS/MealPlate/MealPlate/Cloud/SupabaseCloudStore.swift)、[`migrations/`](../supabase/migrations/) |

这里的关键取舍是**本地先完成记录，再异步同步**。网络暂时不可用时，已有账号仍可查看设备上的记录；待同步操作保留在本地，联网后重试。代码中留有实验性远端图像与拼贴意图接口，但本次 Release 未配置这些服务，今日／本周拼贴使用本地规则与模板；它不是已上线的 AI 功能。

## 查看和运行

使用 Xcode 打开 [`MealPlate.xcodeproj`](../iOS/MealPlate/MealPlate.xcodeproj)，目标平台为 iOS 17 及以上。工程中的 Supabase 地址和 Publishable Key 默认留空；账号及云同步需要接入自己的 Supabase 项目，并应用 [`supabase/migrations/`](../supabase/migrations/) 中的数据库迁移。请将配置写入被 Git 忽略的 `iOS/MealPlate/Configuration/Supabase.local.xcconfig`，不要提交密钥或真实用户数据。

这份源码已通过关闭代码签名的 iPhone `Release` 编译；账号页和拍摄页仍有 Swift 并发隔离警告。编译通过不代表云端配置或所有真机流程都已完成验收。

这个仓库用于展示产品案例、源码与架构，未附开源许可证；餐盘、背景等原创视觉素材仍由作者保留权利。随项目提供的第三方字体及其许可文件见 [`assets/fonts/`](../assets/fonts/)。
