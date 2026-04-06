# 使用真实用户数据调试

## 备份来源

`backup/` 目录包含从用户 iPhone (jmh, iPhone 13) 于 2026-04-06 导出的真实数据：

| 文件 | 说明 |
|------|------|
| `app-container/` | 完整 app 沙盒，含 SwiftData 数据库 |
| `courses-export.csv` | 5 门课程（可读格式） |
| `lessons-export.csv` | 53 节课时（可读格式） |

数据库文件位于 `app-container/Library/Application Support/default.store`（及 `-wal`、`-shm`）。

## 加载到模拟器

### 1. 先运行一次 app（生成沙盒）

```bash
# 构建并启动模拟器
xcodegen generate
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build

# 启动模拟器中的 app（生成沙盒目录后可立即关闭）
xcrun simctl boot "iPhone 16 Pro" 2>/dev/null
xcrun simctl launch booted com.xujifeng.TomatoSchedule
sleep 2
xcrun simctl terminate booted com.xujifeng.TomatoSchedule
```

### 2. 找到模拟器沙盒路径

```bash
SANDBOX=$(xcrun simctl get_app_container booted com.xujifeng.TomatoSchedule data)
echo "沙盒路径: $SANDBOX"
```

### 3. 覆盖数据库文件

```bash
# 确保 app 已关闭
xcrun simctl terminate booted com.xujifeng.TomatoSchedule 2>/dev/null

# 覆盖 SwiftData 数据库（3 个文件）
cp backup/app-container/Library/Application\ Support/default.store \
   "$SANDBOX/Library/Application Support/default.store"

cp backup/app-container/Library/Application\ Support/default.store-wal \
   "$SANDBOX/Library/Application Support/default.store-wal"

cp backup/app-container/Library/Application\ Support/default.store-shm \
   "$SANDBOX/Library/Application Support/default.store-shm"
```

### 4. 启动 app 验证

```bash
xcrun simctl launch booted com.xujifeng.TomatoSchedule
```

打开后应能看到 5 门课程和 53 节课时数据。

## 加载到真机（调试机）

如果要把数据推送到另一台 iPhone：

```bash
DEVICE_ID="<目标设备 UUID>"

xcrun devicectl device copy to \
  --device "$DEVICE_ID" \
  --source backup/app-container/Library/Application\ Support/default.store \
  --destination "Library/Application Support/default.store" \
  --domain-type appDataContainer \
  --domain-identifier com.xujifeng.TomatoSchedule
```

注意：需要先在目标设备上安装并运行一次 app 以生成沙盒。

## 从设备导出新的备份

```bash
DEVICE_ID="<设备 UUID>"

# 查看设备列表
xcrun devicectl list devices

# 导出 app 容器
xcrun devicectl device copy from \
  --device "$DEVICE_ID" \
  --source / \
  --domain-type appDataContainer \
  --domain-identifier com.xujifeng.TomatoSchedule \
  --destination backup/app-container

# 导出为可读 CSV
sqlite3 -header -csv "backup/app-container/Library/Application Support/default.store" \
  "SELECT C.ZNAME AS course, L.ZSTUDENTNAME AS student, \
   datetime(L.ZSTARTTIME + 978307200, 'unixepoch', 'localtime') AS start, \
   datetime(L.ZENDTIME + 978307200, 'unixepoch', 'localtime') AS end, \
   L.ZISCOMPLETED AS completed, L.ZISPRICEOVERRIDDEN AS price_frozen, \
   L.ZPRICEOVERRIDE AS price, L.ZLESSONNUMBER AS lesson_num \
   FROM ZLESSON L LEFT JOIN ZCOURSE C ON L.ZCOURSE = C.Z_PK \
   ORDER BY L.ZSTARTTIME;" > backup/lessons-export.csv
```

## 注意事项

- 覆盖数据库前务必关闭 app，否则 SQLite WAL 锁会导致数据损坏
- V5 更新后首次启动会自动执行 `migrateV5PriceFreeze()`，为旧数据补充 `isManualPrice` 字段
- `backup/` 目录已加入 `.gitignore`，不会提交到仓库（含用户隐私数据）
