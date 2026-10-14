# 餐盘库

`catalog.json` 是餐盘数据的唯一来源。代码不通过扫描图片文件夹推断系列或排序，而是读取此文件中的 `series` 与 `plates`。

目录约定：

```text
plate-library/
|- catalog.json
`- images/
   |- default/
   |- lindsay-rogers-series-1/
   `- lindsay-rogers-series-2/
```

新增一个系列时：

1. 在 `images/` 下建立对应的英文 `series id` 文件夹。
2. 在 `series` 中新增一条系列记录，填写名称、顺序、背景 `backgroundKey`。
3. 在 `plates` 中为每张盘新增一条记录。图片只负责视觉，名称、顺序和系列归属只写在 `catalog.json`。

内置餐盘统一使用 `1280 × 1280`、保留 Alpha 的 PNG。这个尺寸覆盖当前最大约 `300pt @3x` 的真机显示并保留缩放余量；不要重新放入 2048px 原图，否则 38 张餐盘会让安装包增加约 110MB。需要恢复原始 2048px 素材时使用 Git 版本 `7ae3d75`。

每张餐盘将使用以下字段：

```json
{
  "id": "plate-unique-id",
  "seriesId": "default",
  "name": "餐盘名称",
  "displayOrder": 1,
  "imagePath": "images/default/plate-unique-id.png",
  "isAvailable": true
}
```

未来接入线上数据库时，直接将 `series` 与 `plates` 作为两张表或两个 API 资源；前端字段不需要重写。
