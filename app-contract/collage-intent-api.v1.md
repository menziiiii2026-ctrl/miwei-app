# 拼贴意图服务 API v1

此接口只让服务端 AI 在 App 给出的白名单内选择模板、背景、氛围与短文案。它不返回坐标、不生成贴纸、不重画餐盘，也不直接生成最终图片。

## 调用边界

- App 只保存服务端基址 `MealPlateCollageAIAPIBaseURL`，请求路径固定为 `POST /v1/collage-intent`。
- OpenAI 或其他模型供应商的 API Key 只保存在服务端，禁止写入 iOS 工程、Info.plist 或客户端请求头。
- Release 只接受 HTTPS。Debug 可使用 `localhost`、`127.0.0.1`、`.local` 和局域网私有地址的 HTTP 服务。
- 未配置服务、网络失败、超时或响应校验失败时，App 必须回退到本地确定性选择，不阻塞生成。

## 请求

```json
{
  "input": {
    "period": "today",
    "periodStart": "2026-09-14T00:00:00+08:00",
    "periodEnd": "2026-09-15T00:00:00+08:00",
    "foods": [{
      "id": "UUID",
      "dishName": "菜品名",
      "cutoutAssetReference": "Composed/....png",
      "recordedAt": "2026-09-14T12:00:00+08:00",
      "plateID": "plate-id",
      "plateVersion": 1,
      "analysisImage": {"mimeType": "image/jpeg", "imageBase64": "..."}
    }],
    "backgroundCandidates": [{
      "id": "collage-bg-pearl-silk-cotton",
      "assetReference": "editor-assets/backgrounds/collage-bg-pearl-silk-cotton.png",
      "tags": ["珍珠白", "低饱和"],
      "analysisImage": {"mimeType": "image/jpeg", "imageBase64": "..."}
    }],
    "localeIdentifier": "zh_CN",
    "templateCatalogVersion": "template-catalog.v1"
  },
  "allowed_template_codes": ["1_模板1", "1_模板2", "1_模板3"]
}
```

日期由 iOS 的 `JSONEncoder.iso8601` 编码。字段名以当前 Swift `CollageCompositionInput` 的 Codable 输出为准；服务端接入前若要统一 snake_case，必须同时升级接口版本，不能静默改名。

## 响应

响应体必须直接满足 `composition-intent.schema.v1.json`。其中：

- `ranked_template_codes` 必须是请求白名单的子集，按优先级排列；
- `food_count` 必须等于请求菜品数；
- `background_id` 必须引用候选背景；候选为空时只允许本地兜底值 `app-default`；
- `mood.accent_color` 必须是六位十六进制颜色；
- 文案长度必须服从 schema；
- `reason` 仅用于调试和生成元数据，不直接展示给用户。

服务端不得返回模型供应商密钥、自由坐标、任意文件路径、Base64 图片或未审核素材。请求中的 `analysisImage` 只是临时视觉输入；iOS 当前把长边压到 512px 并用 JPEG 0.68 质量编码，服务不落盘保存这些图。

## 当前实现状态

2026-09-15：Node 服务已实现端点、豆包多图输入、超时 / 错误回退、模板与背景白名单校验；iOS 已实现 512px 分析图、意图缓存、manifest 主体布局、Journal 预览缓存与五分钟前台防抖。Debug 指向本机 `.local:8787`，Release 仍为空。实测现有 Key 有效，但 `doubao-seed-2-1-pro-260628` 尚未在当前方舟账号开通；开通前请求会回退到本地确定性方案。
