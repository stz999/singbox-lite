# 链式代理模块 - 部署说明

## 文件

- `chain_proxy.sh` — 链式代理独立模块，可单独运行也可被 singbox.sh 调用

## 部署步骤

### 1. 上传文件到 VPS

```bash
# 将 chain_proxy.sh 上传到与 singbox.sh 同级目录
scp chain_proxy.sh root@<VPS_IP>:/root/
# 或在 VPS 上直接下载
curl -O https://raw.githubusercontent.com/<你的fork>/singbox-lite/main/chain_proxy.sh
```

### 2. 赋予执行权限

```bash
chmod +x /root/chain_proxy.sh
```

### 3. 集成到 singbox.sh 主菜单

编辑 `singbox.sh`，找到「进阶功能」菜单区域，添加第 19 项。

**查找位置的线索**（在 singbox.sh 中搜索）：
```
grep -n "进阶功能\|19\|\"18\"" singbox.sh
```

**添加位置**：在「进阶功能」菜单的 case 分支中，最后一个选项（通常是 `18)` 或类似）之后、`0)` 返回之前，添加：

```bash
# 在 "echo" 打印菜单区域添加一行：
echo -e "${CYAN}║${NC} 19. 链式代理 — AI 流量分流               ${CYAN}║${NC}"

# 在 case "$choice" 区域添加：
19)
    bash "$SCRIPT_DIR/chain_proxy.sh"
    ;;
```

**具体添加示例**（假设当前最大编号是 18）：

```bash
# 1. 找到菜单打印区域（一堆 echo 行），在最后加入：
#    echo -e "${CYAN}║${NC} 19. 链式代理 — AI 流量分流               ${CYAN}║${NC}"

# 2. 找到 case 分支，在 ;; 和 0) 之间加入:
            19)
                bash "$SCRIPT_DIR/chain_proxy.sh"
                ;;
```

### 4. 重启脚本

```bash
./singbox.sh
# 进入进阶功能 → 选择 19 链式代理
```

---

## 独立运行

```bash
./chain_proxy.sh
```

---

## 功能清单

| 选项 | 功能 |
|------|------|
| 1. 添加下一跳代理 | 粘贴 ss:// vless:// vmess:// trojan:// hy2:// socks5:// 链接 |
| 2. 查看状态 | 显示当前 outbound、路由规则数、覆盖域名列表 |
| 3. 管理分流域名 | 追加/删除自定义域名（本次会话有效） |
| 4. 启用/禁用 | 一键开关，仅移除路由规则，节点保留 |
| 5. 删除链式代理 | 完全清除 outbound + 路由规则 |
| 6. 路由测试命令 | 显示 curl 测试和日志过滤命令 |

---

## 工作流程

```
用户粘贴下一跳链接
       ↓
parser.sh 解析为 sing-box outbound
       ↓
写入 config.json (outbounds)
       ↓
注入 route.rules（AI 域名 → chain-ai）
       ↓
重启 sing-box 生效
```

## Sing-box 配置结构

```jsonc
// 新增的 outbound
{
  "tag": "chain-ai",
  "type": "shadowsocks",        // 根据链接自动检测
  "server": "1.2.3.4",
  "server_port": 8388,
  "method": "2022-blake3-aes-256-gcm",
  "password": "xxx",
  "detour": "direct-out"       // 直连下一跳，避免递归
}

// 新增的 route rules（插入到 rules 数组最前面，优先级最高）
[
  {"domain_suffix": ["google.com"], "outbound": "chain-ai"},
  {"domain_suffix": ["googleapis.com"], "outbound": "chain-ai"},
  // ... 40+ AI 域名 ...
  {"domain_keyword": ["gemini", "generativelanguage", ...], "outbound": "chain-ai"}
]
```

## 激进版 AI 域名覆盖

### 全后缀覆盖
- Google 全家桶全子域: google.com, googleapis.com, gstatic.com, googleusercontent.com, 1e100.net
- Android GMS/Firebase: firebaseio.com, firebaseapp.com, app-measurement.com, gvt2.com, gvt3.com
- OpenAI: openai.com, chatgpt.com, oaistatic.com, sora.com
- Anthropic: anthropic.com, claude.ai
- Google AI: deepmind.com, bard.google.com, aistudio.google.com, ai.google.dev, makersuite.google.com
- 其他 AI: perplexity.ai, groq.com, deepseek.com, openrouter.ai, cohere.com, together.ai, mistral.ai, x.ai, poe.com, you.com, phind.com, character.ai
- AI 编程: githubcopilot.com, cursor.sh, windsurf.com, codeium.com, tabnine.com, sourcegraph.com

### 关键词兜底
gemini, generativelanguage, alkalimakersuite, proactiveagent, deepmind, bard, notebooklm, colab

---

## 注意事项

1. **必须先安装好 sing-box** 并已有 config.json
2. **parser.sh 必须存在** 于同目录（chain_proxy.sh 会调用它解析链接）
3. **重启 sing-box 后才生效**（脚本会询问是否自动重启）
4. **备份自动生成** `config.json.chain.bak`
5. **重启后规则插入到 rules 最前面**，优先级高于其他路由规则
