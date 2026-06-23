#!/bin/bash

# ============================================================
# chain_proxy.sh — singbox-lite 链式代理模块
# 功能：输入下一跳代理地址，将 AI 流量分流过去
# 可独立运行，也可由 singbox.sh 进阶菜单调用
# ============================================================

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
SINGBOX_DIR="/usr/local/etc/sing-box"
CONFIG_FILE="${SINGBOX_DIR}/config.json"
CLASH_YAML="${SINGBOX_DIR}/clash.yaml"
CHAIN_META="${SINGBOX_DIR}/chain_meta.json"
CHAIN_ROUTE_TAG="chain-ai"

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
ORANGE='\033[0;33m'

_info()  { echo -e "${CYAN}[信息] $1${NC}" >&2; }
_success() { echo -e "${GREEN}[成功] $1${NC}" >&2; }
_warn()  { echo -e "${YELLOW}[注意] $1${NC}" >&2; }
_error() { echo -e "${RED}[错误] $1${NC}" >&2; }

_check_root() {
    if [[ $EUID -ne 0 ]]; then
        _error "此脚本必须以 root 权限运行。"
        exit 1
    fi
}

# ---- 从父脚本继承函数（若已 source）----
# 若独立运行，定义最小兜底
if ! declare -f _atomic_modify_json >/dev/null 2>&1; then
    _atomic_modify_json() {
        local file="$1" filter="$2"
        [ ! -f "$file" ] && return 1
        local tmp="${file}.tmp"
        if jq "$filter" "$file" > "$tmp"; then mv "$tmp" "$file"
        else _error "修改JSON失败: $file"; rm -f "$tmp"; return 1; fi
    }
fi

if ! declare -f _url_decode >/dev/null 2>&1; then
    _url_decode() {
        local data="${1//+/ }"
        printf '%b' "${data//%/\\x}"
    }
fi

if ! declare -f _get_public_ip >/dev/null 2>&1; then
    _get_public_ip() {
        [ -n "$server_ip" ] && [ "$server_ip" != "null" ] && { echo "$server_ip"; return; }
        local ip=$(timeout 5 curl -s4 --max-time 2 icanhazip.com 2>/dev/null || timeout 5 curl -s4 --max-time 2 ipinfo.io/ip 2>/dev/null)
        [ -z "$ip" ] && ip=$(timeout 5 curl -s6 --max-time 2 icanhazip.com 2>/dev/null || timeout 5 curl -s6 --max-time 2 ipinfo.io/ip 2>/dev/null)
        server_ip="$ip"
        echo "$ip"
    }
fi

# ---- 链接解析（内嵌，避免 parser.sh 回显到 stdout 干扰）----
_chain_parse_link() {
    local link="$1"
    case "$link" in
        vless://*)   bash "$SCRIPT_DIR/parser.sh" "$link" 2>/dev/null ;;
        vmess://*)   bash "$SCRIPT_DIR/parser.sh" "$link" 2>/dev/null ;;
        trojan://*)  bash "$SCRIPT_DIR/parser.sh" "$link" 2>/dev/null ;;
        ss://*)      bash "$SCRIPT_DIR/parser.sh" "$link" 2>/dev/null ;;
        hy2://*|hysteria2://*)  bash "$SCRIPT_DIR/parser.sh" "$link" 2>/dev/null ;;
        tuic://*)    bash "$SCRIPT_DIR/parser.sh" "$link" 2>/dev/null ;;
        socks5://*)  bash "$SCRIPT_DIR/parser.sh" "$link" 2>/dev/null ;;
        *)           echo "{}" ;;
    esac
}

# ---- 激进版 AI 域名列表 ----
_CHAIN_AI_DOMAINS=(
    # === Google AI 核心 ===
    "google.com"               # 全站覆盖
    "googleapis.com"           # 所有 Google API
    "gstatic.com"              # Google 静态资源
    "googleusercontent.com"    # 用户内容（含 Gemini 图片生成）
    "1e100.net"                # Google 服务器基础设施

    # === Firebase / Android GMS (Gemini 必需) ===
    "firebaseio.com"
    "firebaseapp.com"
    "app-measurement.com"
    "gvt2.com"
    "gvt3.com"
    "googlehosted.com"

    # === OpenAI ===
    "openai.com"
    "chatgpt.com"
    "oaistatic.com"
    "sora.com"

    # === Anthropic / Claude ===
    "anthropic.com"
    "claude.ai"

    # === Google AI 子域名（冗余兜底） ===
    "deepmind.com"
    "makersuite.google.com"
    "aistudio.google.com"
    "ai.google.dev"
    "bard.google.com"

    # === 其他 AI 平台 ===
    "perplexity.ai"
    "groq.com"
    "deepseek.com"
    "openrouter.ai"
    "cohere.com"
    "together.ai"
    "mistral.ai"
    "x.ai"
    "poe.com"
    "you.com"
    "phind.com"
    "character.ai"
    "replicate.com"
    "huggingface.co"
    "civitai.com"

    # === AI 编程工具 ===
    "githubcopilot.com"
    "cursor.sh"
    "windsurf.com"
    "codeium.com"
    "tabnine.com"
    "sourcegraph.com"
)

# ---- 域名关键词兜底 ----
_CHAIN_AI_KEYWORDS=(
    "gemini"
    "generativelanguage"
    "alkalimakersuite"
    "proactiveagent"
    "deepmind"
    "bard"
    "notebooklm"
    "colab"
)

# ---- 状态文件管理 ----
_chain_load_state() {
    [ -f "$CHAIN_META" ] && jq '.' "$CHAIN_META" 2>/dev/null || echo '{"enabled": false, "nodes": {}}'
}

_chain_save_state() {
    echo "$1" | jq '.' > "$CHAIN_META" 2>/dev/null
}

# ---- 解析链接并生成 outbound ----
_chain_build_outbound() {
    local link="$1"
    local name="$2"
    local raw_json
    raw_json=$(_chain_parse_link "$link")

    [ -z "$raw_json" ] || [ "$raw_json" == "{}" ] && {
        _error "无法解析链接: $link"
        return 1
    }

    # 替换 tag 为唯一标识
    local outbound
    outbound=$(echo "$raw_json" | jq --arg tag "$CHAIN_ROUTE_TAG" '
        .tag = $tag |
        .detour = "direct-out"
    ')

    [ -z "$outbound" ] && { _error "生成 outbound 失败"; return 1; }
    echo "$outbound"
}

# ---- 生成路由规则 ----
_chain_build_rules() {
    local rules_json="[]"

    # 1. 精匹配域名（domain_suffix）
    for domain in "${_CHAIN_AI_DOMAINS[@]}"; do
        rules_json=$(echo "$rules_json" | jq --arg domain "$domain" \
            '. + [{domain_suffix: [$domain], outbound: $CHAIN_TAG}]' \
            --arg CHAIN_TAG "$CHAIN_ROUTE_TAG")
    done

    # 2. 域名关键词兜底（domain_keyword）
    local kw_json="[]"
    for kw in "${_CHAIN_AI_KEYWORDS[@]}"; do
        kw_json=$(echo "$kw_json" | jq --arg kw "$kw" '. + [$kw]')
    done
    rules_json=$(echo "$rules_json" | jq --argjson kws "$kw_json" --arg tag "$CHAIN_ROUTE_TAG" \
        '. + [{domain_keyword: $kws, outbound: $tag}]')

    echo "$rules_json"
}

# ---- 添加链式代理节点 ----
_chain_add_node() {
    _info "========== 添加链式代理节点 =========="
    echo ""
    _info "支持格式: ss:// | vless:// | vmess:// | trojan:// | hy2:// | tuic:// | socks5://"
    _info "示例: ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNToxMjM0NTY@1.2.3.4:8388#下一跳"
    echo ""
    read -rp "请输入下一跳代理链接: " next_hop_link

    [ -z "$next_hop_link" ] && { _warn "未输入链接，已取消。"; return 0; }

    # 提取节点名
    local node_name=""
    if [[ "$next_hop_link" == *"#"* ]]; then
        node_name=$(_url_decode "${next_hop_link##*#}")
    else
        node_name="下一跳-$(date +%s)"
    fi

    _info "解析链接: ${node_name} ..."
    local outbound
    outbound=$(_chain_build_outbound "$next_hop_link" "$node_name")

    [ $? -ne 0 ] || [ -z "$outbound" ] && {
        _error "解析失败，请检查链接格式。"
        return 1
    }

    # 显示解析结果
    echo ""
    _info "解析结果:"
    echo "$outbound" | jq '{type, server, server_port, tls: .tls.enabled // false, transport: .transport.type // "direct"}'
    echo ""

    read -rp "确认添加？[Y/n]: " confirm
    [[ "$confirm" == "n" || "$confirm" == "N" ]] && { _warn "已取消。"; return 0; }

    # 备份配置
    cp "$CONFIG_FILE" "${CONFIG_FILE}.chain.bak" 2>/dev/null

    # 删除旧链式代理 outbound（若存在）
    _atomic_modify_json "$CONFIG_FILE" "del(.outbounds[] | select(.tag == \"$CHAIN_ROUTE_TAG\"))" 2>/dev/null

    # 添加新 outbound
    _atomic_modify_json "$CONFIG_FILE" ".outbounds += [${outbound}]"

    # 移除旧链式路由规则
    _atomic_modify_json "$CONFIG_FILE" "del(.route.rules[] | select(.outbound == \"$CHAIN_ROUTE_TAG\"))" 2>/dev/null

    # 添加 AI 路由规则（插入到 rule_set 规则之前，即优先级最高）
    local rules
    rules=$(_chain_build_rules)
    local rule_array
    rule_array=$(echo "$rules" | jq -c '.')
    _atomic_modify_json "$CONFIG_FILE" ".route.rules = (${rule_array} + .route.rules)"

    # 保存元数据
    local state
    state=$(_chain_load_state)
    state=$(echo "$state" | jq --arg name "$node_name" --arg link "$next_hop_link" --arg outbound "$outbound" '
        .enabled = true |
        .nodes[.current // $name] = {
            name: $name,
            link: $link,
            added_at: (now | strftime("%Y-%m-%d %H:%M:%S"))
        } |
        .current = $name
    ')
    _chain_save_state "$state"

    # 更新 Clash YAML（如存在）
    if [ -f "${SINGBOX_DIR}/clash.yaml" ] && command -v "$YQ_BINARY" &>/dev/null; then
        _info "同步到 Clash YAML..."
        export YQ_BIN="${YQ_BINARY:-/usr/local/bin/yq}"
        local clash_proxy
        clash_proxy=$(echo "$outbound" | jq --arg name "$CHAIN_ROUTE_TAG" '
            .name = $name |
            .server = .server |
            .port = .server_port |
            del(.server_port) |
            del(.detour) |
            del(.tag)
        ') 2>/dev/null
        if [ -n "$clash_proxy" ]; then
            # 确保有对应的代理组
            if ! "$YQ_BIN" eval '.proxy-groups[] | select(.name == "AI链式")' "$CLASH_YAML" 2>/dev/null | grep -q .; then
                "$YQ_BIN" eval -i '.proxy-groups += [{"name":"AI链式","type":"select","proxies":["DIRECT"]}]' "$CLASH_YAML" 2>/dev/null
            fi
        fi
    fi

    _success "链式代理已添加！"
    _success "节点名称: ${node_name}"
    _success "出站标签: ${CHAIN_ROUTE_TAG}"
    echo ""
    _warn "=============================="
    _warn "| 请重启 sing-box 使配置生效 |"
    _warn "| 执行: sing-box restart     |"
    _warn "=============================="
    echo ""

    read -rp "是否立即重启 sing-box？[Y/n]: " do_restart
    [[ "$do_restart" != "n" && "$do_restart" != "N" ]] && {
        _info "正在重启 sing-box..."
        systemctl restart sing-box 2>/dev/null || rc-service sing-box restart 2>/dev/null || {
            _warn "无法自动重启，请手动重启 sing-box。"
        }
    }
}

# ---- 查看状态 ----
_chain_show_status() {
    _info "========== 链式代理状态 =========="
    echo ""

    local state
    state=$(_chain_load_state)

    local enabled
    enabled=$(echo "$state" | jq -r '.enabled // false')
    local current
    current=$(echo "$state" | jq -r '.current // "无"')

    echo -e "状态: $([ "$enabled" == "true" ] && echo -e "${GREEN}已启用${NC}" || echo -e "${RED}已禁用${NC}")"
    echo -e "当前节点: ${CYAN}${current}${NC}"
    echo ""

    # 检查配置文件中是否存在链式 outbound
    if [ -f "$CONFIG_FILE" ]; then
        local has_chain
        has_chain=$(jq -r '.outbounds[] | select(.tag == $tag) | .type' --arg tag "$CHAIN_ROUTE_TAG" "$CONFIG_FILE" 2>/dev/null)
        [ -n "$has_chain" ] && {
            echo "┌─ Outbound ─────────────────────────────────"
            jq '.outbounds[] | select(.tag == $tag)' --arg tag "$CHAIN_ROUTE_TAG" "$CONFIG_FILE" | \
                jq '{类型: .type, 服务器: .server, 端口: .server_port, TLS: (.tls.enabled // false)}'
        }

        local has_rules
        has_rules=$(jq -r '[.route.rules[] | select(.outbound == $tag)] | length' --arg tag "$CHAIN_ROUTE_TAG" "$CONFIG_FILE" 2>/dev/null)
        [ "$has_rules" -gt 0 ] 2>/dev/null && {
            echo "├─ Route Rules ───────────────────────────────"
            echo -e "  分流规则数: ${CYAN}${has_rules}${NC} 条"
            echo ""
            echo "  覆盖域名 (前20):"
            jq -r '.route.rules[] | select(.outbound == $tag) | .domain_suffix[]?' --arg tag "$CHAIN_ROUTE_TAG" "$CONFIG_FILE" 2>/dev/null | head -20 | sed 's/^/    /'
        }
        echo "└────────────────────────────────────────────"
    else
        _warn "配置文件 ${CONFIG_FILE} 不存在。"
    fi
    echo ""

    # 显示历史节点
    local node_count
    node_count=$(echo "$state" | jq '.nodes | length // 0' 2>/dev/null)
    [ "$node_count" -gt 0 ] 2>/dev/null && {
        echo -e "${CYAN}历史节点 (${node_count}):${NC}"
        echo "$state" | jq -r '.nodes | to_entries[] | "  [\(.key)] \(.value.name) — \(.value.added_at)"' 2>/dev/null
        echo ""
    }
}

# ---- 管理 AI 域名 ----
_chain_manage_domains() {
    while true; do
        echo ""
        _info "========== 管理分流域名 =========="
        echo ""
        echo "当前 AI 域名 (${#_CHAIN_AI_DOMAINS[@]} 个):"
        echo "────────────────────────────────────────────"
        local i=1
        for d in "${_CHAIN_AI_DOMAINS[@]}"; do
            printf "  %2d. %s\n" "$i" "$d"
            ((i++))
        done
        echo "────────────────────────────────────────────"
        echo ""
        echo "关键词兜底 (${#_CHAIN_AI_KEYWORDS[@]} 个):"
        echo "  ${_CHAIN_AI_KEYWORDS[*]}"
        echo ""
        echo "  1. 添加自定义域名"
        echo "  2. 删除域名"
        echo "  3. 恢复默认域名列表"
        echo "  0. 返回"
        echo ""
        read -rp "请选择 [0-3]: " choice

        case "$choice" in
            1)
                read -rp "输入要追加的域名 (如 example.com): " new_domain
                [ -z "$new_domain" ] && continue
                _CHAIN_AI_DOMAINS+=("$new_domain")
                _info "已添加: ${new_domain}"
                _info "⚠ 修改仅对本次会话生效，下次运行脚本将恢复默认列表。"
                _info "⚠ 如需永久修改，请编辑脚本中的 _CHAIN_AI_DOMAINS 数组。"
                ;;
            2)
                read -rp "输入要删除的域名: " del_domain
                [ -z "$del_domain" ] && continue
                local found=false
                local new_domains=()
                for d in "${_CHAIN_AI_DOMAINS[@]}"; do
                    [ "$d" == "$del_domain" ] && found=true && continue
                    new_domains+=("$d")
                done
                if $found; then
                    _CHAIN_AI_DOMAINS=("${new_domains[@]}")
                    _info "已删除: ${del_domain}"
                else
                    _warn "未找到域名: ${del_domain}"
                fi
                ;;
            3)
                _info "请编辑脚本文件，将 _CHAIN_AI_DOMAINS 数组替换为默认值后重新运行。"
                ;;
            0)
                return
                ;;
            *) _warn "无效选择。" ;;
        esac
    done
}

# ---- 删除链式代理 ----
_chain_remove() {
    _info "========== 删除链式代理 =========="
    echo ""

    local state
    state=$(_chain_load_state)
    local has_chain
    has_chain=$(jq -r '.outbounds[] | select(.tag == $tag) | .type' --arg tag "$CHAIN_ROUTE_TAG" "$CONFIG_FILE" 2>/dev/null)

    if [ -z "$has_chain" ]; then
        _warn "当前没有配置链式代理。"
        return 0
    fi

    echo "将删除以下内容:"
    echo "  - outbound: ${CHAIN_ROUTE_TAG}"
    echo "  - 所有 AI 分流路由规则"
    echo ""

    read -rp "确认删除？输入 yes 确认: " confirm
    [ "$confirm" != "yes" ] && { _warn "已取消。"; return 0; }

    cp "$CONFIG_FILE" "${CONFIG_FILE}.chain.bak" 2>/dev/null

    # 删除 outbound
    _atomic_modify_json "$CONFIG_FILE" "del(.outbounds[] | select(.tag == \"$CHAIN_ROUTE_TAG\"))" 2>/dev/null

    # 删除路由规则
    _atomic_modify_json "$CONFIG_FILE" "del(.route.rules[] | select(.outbound == \"$CHAIN_ROUTE_TAG\"))" 2>/dev/null

    # 更新状态文件
    state=$(echo "$state" | jq '.enabled = false')
    _chain_save_state "$state"

    _success "链式代理已删除。"
    _warn "请重启 sing-box 使配置生效。"
}

# ---- 启用/禁用 ----
_chain_toggle() {
    local state
    state=$(_chain_load_state)
    local enabled
    enabled=$(echo "$state" | jq -r '.enabled // false')

    if [ "$enabled" == "true" ]; then
        _info "当前状态: 已启用 → 禁用中..."
        # 禁用：仅移除路由规则，保留 outbound
        cp "$CONFIG_FILE" "${CONFIG_FILE}.chain.bak" 2>/dev/null
        _atomic_modify_json "$CONFIG_FILE" "del(.route.rules[] | select(.outbound == \"$CHAIN_ROUTE_TAG\"))" 2>/dev/null
        state=$(echo "$state" | jq '.enabled = false')
        _chain_save_state "$state"
        _success "链式代理已禁用（规则已移除，节点保留）。"
    else
        _info "当前状态: 已禁用 → 启用中..."

        # 检查 outbound 是否存在
        local has_outbound
        has_outbound=$(jq -r '.outbounds[] | select(.tag == $tag) | .type' --arg tag "$CHAIN_ROUTE_TAG" "$CONFIG_FILE" 2>/dev/null)
        if [ -z "$has_outbound" ]; then
            _error "未找到链式代理节点，请先添加节点。"
            return 1
        fi

        cp "$CONFIG_FILE" "${CONFIG_FILE}.chain.bak" 2>/dev/null

        # 先清旧规则
        _atomic_modify_json "$CONFIG_FILE" "del(.route.rules[] | select(.outbound == \"$CHAIN_ROUTE_TAG\"))" 2>/dev/null

        # 重新添加规则
        local rules
        rules=$(_chain_build_rules)
        local rule_array
        rule_array=$(echo "$rules" | jq -c '.')
        _atomic_modify_json "$CONFIG_FILE" ".route.rules = (${rule_array} + .route.rules)"

        state=$(echo "$state" | jq '.enabled = true')
        _chain_save_state "$state"
        _success "链式代理已启用。"
    fi

    _warn "请重启 sing-box 使配置生效。"
}

# ---- 显示路由测试信息 ----
_chain_test_info() {
    _info "========== 路由测试 =========="
    echo ""
    echo "重启 sing-box 后，使用以下命令验证:"
    echo ""
    echo "  # 测试 Gemini 连接"
    echo "  curl -x http://127.0.0.1:<HTTP代理端口> https://gemini.google.com/ -I"
    echo ""
    echo "  # 测试 OpenAI"
    echo "  curl -x http://127.0.0.1:<HTTP代理端口> https://api.openai.com/v1/models -I"
    echo ""
    echo "  # 查看 sing-box 日志，确认流量走链式代理"
    echo "  journalctl -u sing-box -f | grep ${CHAIN_ROUTE_TAG}"
    echo ""
}

# ---- 主菜单 ----
chain_proxy_menu() {
    _check_root
    while true; do
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║       🔗 链式代理管理 (Chain AI)    ║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  1. 添加下一跳代理                  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  2. 查看状态 & 路由详情             ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  3. 管理分流域名                    ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  4. 启用 / 禁用链式代理              ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  5. 删除链式代理                     ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  6. 路由测试命令                     ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  0. 返回主菜单                       ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
        echo ""
        read -rp "请选择 [0-6]: " choice

        case "$choice" in
            1) _chain_add_node ;;
            2) _chain_show_status ;;
            3) _chain_manage_domains ;;
            4) _chain_toggle ;;
            5) _chain_remove ;;
            6) _chain_test_info ;;
            0) return 0 ;;
            *) _warn "请输入 0-6 之间的数字。" ;;
        esac
    done
}

# ---- 独立运行入口 ----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    chain_proxy_menu "$@"
fi
