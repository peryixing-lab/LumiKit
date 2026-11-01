# LumiKit 原生集成验证

此 runner 使用真实 HarmonyOS SDK，测试生产代码 `processFiles`（通过 TaskPool 执行）和 `DeveloperRuntime`，不使用 mock。需要支持 PDF Kit 的 API 26 HarmonyOS 设备或模拟器。

先构建并安装同一签名下的主 HAP 与 `entry@ohosTest` 测试 HAP；随后运行：

```sh
hdc -t '<设备序列号>' shell aa test -b com.lovexjy.LumiKit -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 120000 -w 300
```

可仅运行本测试集合：

```sh
hdc -t '<设备序列号>' shell aa test -b com.lovexjy.LumiKit -m entry_test -s unittest OpenHarmonyTestRunner -s class LumiKitNativeIntegration -s timeout 120000 -w 300
```

`List.test.ets` 仅注册 `LumiKitNativeIntegration`，不会运行旧脚手架的占位断言。

覆盖 16 项：PNG 原生像素 fixture；PNG/JPEG/WebP 转码与等比缩放；PDF 文本与矢量结构往返；PDF 合并的顺序/尺寸/文本保留；PDF 拆分；PDF 提取；PDF 到 PNG 的真实渲染与可见墨迹；图片到 A4 PDF；非法页码拒绝且不发布结果；SHA-256 空文本/ASCII/UTF-8 已知向量；100 个真实 UUID v4 的格式与唯一性；原生 TaskPool 正则；RDB 关闭重开后的持久化；RDB 失败回滚与成功提交的原子更新。

本轮新增 **5 项边界用例，尚未运行或构建，不计入既有 16/16 通过结果**：

- 截断且缺少页树/xref/trailer 的损坏 PDF；普通文本伪装为 `.pdf`；真实 PNG 字节伪装为 `.pdf`。分别调用生产 `openPDF`，再通过真实 TaskPool 调用合并、拆分、提取和渲染，要求拒绝、输出前缀下没有最终/派生/临时文件、坏输入与正常合并源逐字节不变。
- 使用安装 SDK 声明的 `TextAnnotationInfo` / `PdfPage.addAnnotation` 创建文字批注，保存后先由 PDF Kit 重新解析批注类型与内容，再验证其处于第一个/第二个合并输入时均命中“含链接或批注”保护，且输入字节完全不变。
- 安装 SDK 的 `PdfAnnotationInfo.action` 明确仅支持读取现有链接，不能新增/编辑；因此链接 fixture 由测试直接写入带标准 `/Link` 与 `/URI` 字典及正确 xref 偏移的 ASCII PDF。测试先要求真实 PDF Kit 解析出可搜索文字、LINK 类型和精确 URI，再验证两个合并顺序的拒绝与源文件不变。不会调用不存在的 SDK 链接写入 API，也不会打开 URI 或联网。

这些用例只观察本次隔离目录的实际磁盘输出，不访问业务工作区索引或 StorageService。新增用例失败不会被记为通过；需由后续真实设备/模拟器执行结果更新验证报告。

测试先通过 `application.createModuleContext(getAppContext().getApplicationContext(), 'entry')` 获取真实 Stage 模块上下文（直接使用 delegator 的 app context 会被 RDB 拒绝）。全部文件 fixture 在该上下文的 `cacheDir/lumikit-validation/run_<本次token>/`。RDB 的 SDK `rootDir` 仅支持只读打开，因此可写数据库采用独立 `databaseDir/rdb/lumikit-validation/lumikit_validation_<本次token>_*.db`，清理时仅调用这些唯一配置的 `deleteRdbStore`。不会打开业务 `StorageService`，不会更改工作区索引、物品、表单、分析项目或历史。

完成后删除本次生成的文件和测试数据库，保留 `cacheDir/lumikit-validation/report_<token>.json`。runner 同时输出：

- `LUMIKIT_NATIVE_REPORT`：报告路径。
- `LUMIKIT_NATIVE_SUMMARY`：通过数 / 实际执行数。
- 完整 JSON 报告：每项结果、耗时与失败原因，以及 fixture 清理状态。

不支持 WebP/PDF 会明确失败，不能据此记作验证通过。若 beforeAll fixture 初始化失败，应先排查测试输出中的字体/PDF SDK 错误，不能把缺失执行项视为通过。

`FormPdfService` 没有在此套件直接调用：它内部注册真实 FileService 工作区并使用业务 StorageService，因此直接调用会违反本测试的数据隔离约束。表单模板/回答 PDF 应由模拟器 UI 验证；底层原生 PDF 文本、结构、渲染能力由本套件验证。
