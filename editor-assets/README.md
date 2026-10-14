# 分享拼贴编辑器素材库

`editor-assets/` 只存放“今日 / 本周”分享拼贴编辑器使用的可替换素材。

- `backgrounds/`：画布可选背景。运行时从 Bundle 的 `editor-assets/backgrounds` 读取。
- 文件名使用 `collage-bg-*`，不使用 `app-bg-*` 或 `background-*`。
- 这些素材可被用户替换，也会进入最终导出图。

当前已接入 12 张专用编辑器背景，统一转换为 PNG 并使用 `collage-bg-*` 命名。代码不读取原 App 背景路径。

## 上传专用背景

1. 将新背景 PNG 放进 `editor-assets/backgrounds/`，不要放进 `background-assets/`。
2. 文件名统一使用英文小写的 `collage-bg-*.png`，例如 `collage-bg-warm-tablecloth.png`。
3. 推荐使用 `3:4` 竖图，至少 `1206 × 1608px`，以覆盖 `402 × 536pt @3x` 导出；其他比例会在画布中居中裁切。
4. 新文件放好后，需要在 `CollageEditorAssetLibrary.backgroundNames` 与 `backgroundTags(for:)` 中登记，AI 和背景选择面板才会读取。

App 页面自身的背景仍存放在 `background-assets/`，只允许 `AppBackground` 使用。两个目录不得交叉读取，避免替换编辑器素材时意外改变 App 页面。
