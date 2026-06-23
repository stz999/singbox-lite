#!/bin/bash

# ============================================================
# chain_proxy.sh 鈥?singbox-lite 閾惧紡浠ｇ悊妯″潡
# 鍔熻兘锛氳緭鍏ヤ笅涓€璺充唬鐞嗗湴鍧€锛屽皢 AI 娴侀噺鍒嗘祦杩囧幓
# 鍙嫭绔嬭繍琛岋紝涔熷彲鐢?singbox.sh 杩涢樁鑿滃崟璋冪敤
# ============================================================

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
SINGBOX_DIR="/usr/local/etc/sing-box"
CONFIG_FILE="${SINGBOX_DIR}/config.json"
CLASH_YAML="${SINGBOX_DIR}/clash.yaml"
CHAIN_META="${SINGBOX_DIR}/chain_meta.json"
CHAIN_ROUTE_TAG="chain-ai"

# ---- 棰滆壊 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
ORANGE='\033[0;33m'

_info()  { echo -e "${CYAN}[淇℃伅] $1${NC}" >&2; }
_success() { echo -e "${GREEN}[鎴愬姛] $1${NC}" >&2; }
_warn()  { echo -e "${YELLOW}[娉ㄦ剰] $1${NC}" >&2; }
_error() { echo -e "${RED}[閿欒] $1${NC}" >&2; }

_check_root() {
    if [[ $EUID -ne 0 ]]; then
        _error "姝よ剼鏈繀椤讳互 root 鏉冮檺杩愯銆?
        exit 1
    fi
}

# ---- 浠庣埗鑴氭湰缁ф壙鍑芥暟锛堣嫢宸?source锛?---
# 鑻ョ嫭绔嬭繍琛岋紝瀹氫箟鏈€灏忓厹搴?if ! declare -f _atomic_modify_json >/dev/null 2>&1; then
    _atomic_modify_json() {
        local file="$1" filter="$2"
        [ ! -f "$file" ] && return 1
        local tmp="${file}.tmp"
        if jq "$filter" "$file" > "$tmp"; then mv "$tmp" "$file"
        else _error "淇敼JSON澶辫触: $file"; rm -f "$tmp"; return 1; fi
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

# ---- 閾炬帴瑙ｆ瀽锛堝唴宓岋紝閬垮厤 parser.sh 鍥炴樉鍒?stdout 骞叉壈锛?---
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

# ---- 婵€杩涚増 AI 鍩熷悕鍒楄〃 ----
_CHAIN_AI_DOMAINS=(
    # === Google AI 鏍稿績 ===
    "google.com"               # 鍏ㄧ珯瑕嗙洊
    "googleapis.com"           # 鎵€鏈?Google API
    "gstatic.com"              # Google 闈欐€佽祫婧?    "googleusercontent.com"    # 鐢ㄦ埛鍐呭锛堝惈 Gemini 鍥剧墖鐢熸垚锛?    "1e100.net"                # Google 鏈嶅姟鍣ㄥ熀纭€璁炬柦

    # === Firebase / Android GMS (Gemini 蹇呴渶) ===
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

    # === Google AI 瀛愬煙鍚嶏紙鍐椾綑鍏滃簳锛?===
    "deepmind.com"
    "makersuite.google.com"
    "aistudio.google.com"
    "ai.google.dev"
    "bard.google.com"

    # === 鍏朵粬 AI 骞冲彴 ===
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

    # === AI 缂栫▼宸ュ叿 ===
    "githubcopilot.com"
    "cursor.sh"
    "windsurf.com"
    "codeium.com"
    "tabnine.com"
    "sourcegraph.com"
)

# ---- 鍩熷悕鍏抽敭璇嶅厹搴?----
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

# ---- 鐘舵€佹枃浠剁鐞?----
_chain_load_state() {
    [ -f "$CHAIN_META" ] && jq '.' "$CHAIN_META" 2>/dev/null || echo '{"enabled": false, "nodes": {}}'
}

_chain_save_state() {
    echo "$1" | jq '.' > "$CHAIN_META" 2>/dev/null
}

# ---- 瑙ｆ瀽閾炬帴骞剁敓鎴?outbound ----
_chain_build_outbound() {
    local link="$1"
    local name="$2"
    local raw_json
    raw_json=$(_chain_parse_link "$link")

    [ -z "$raw_json" ] || [ "$raw_json" == "{}" ] && {
        _error "鏃犳硶瑙ｆ瀽閾炬帴: $link"
        return 1
    }

    # 鏇挎崲 tag 涓哄敮涓€鏍囪瘑
    local outbound
    outbound=$(echo "$raw_json" | jq --arg tag "$CHAIN_ROUTE_TAG" '
        .tag = $tag |
        .detour = "direct-out"
    ')

    [ -z "$outbound" ] && { _error "鐢熸垚 outbound 澶辫触"; return 1; }
    echo "$outbound"
}

# ---- 鐢熸垚璺敱瑙勫垯 ----
_chain_build_rules() {
    local rules_json="[]"

    # 1. 绮惧尮閰嶅煙鍚嶏紙domain_suffix锛?    for domain in "${_CHAIN_AI_DOMAINS[@]}"; do
        rules_json=$(echo "$rules_json" | jq --arg domain "$domain" \
            '. + [{domain_suffix: [$domain], outbound: $CHAIN_TAG}]' \
            --arg CHAIN_TAG "$CHAIN_ROUTE_TAG")
    done

    # 2. 鍩熷悕鍏抽敭璇嶅厹搴曪紙domain_keyword锛?    local kw_json="[]"
    for kw in "${_CHAIN_AI_KEYWORDS[@]}"; do
        kw_json=$(echo "$kw_json" | jq --arg kw "$kw" '. + [$kw]')
    done
    rules_json=$(echo "$rules_json" | jq --argjson kws "$kw_json" --arg tag "$CHAIN_ROUTE_TAG" \
        '. + [{domain_keyword: $kws, outbound: $tag}]')

    echo "$rules_json"
}

# ---- 娣诲姞閾惧紡浠ｇ悊鑺傜偣 ----
_chain_add_node() {
    _info "========== 娣诲姞閾惧紡浠ｇ悊鑺傜偣 =========="
    echo ""
    _info "鏀寔鏍煎紡: ss:// | vless:// | vmess:// | trojan:// | hy2:// | tuic:// | socks5://"
    _info "绀轰緥: ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNToxMjM0NTY@1.2.3.4:8388#涓嬩竴璺?
    echo ""
    read -rp "璇疯緭鍏ヤ笅涓€璺充唬鐞嗛摼鎺? " next_hop_link

    [ -z "$next_hop_link" ] && { _warn "鏈緭鍏ラ摼鎺ワ紝宸插彇娑堛€?; return 0; }

    # 鎻愬彇鑺傜偣鍚?    local node_name=""
    if [[ "$next_hop_link" == *"#"* ]]; then
        node_name=$(_url_decode "${next_hop_link##*#}")
    else
        node_name="涓嬩竴璺?$(date +%s)"
    fi

    _info "瑙ｆ瀽閾炬帴: ${node_name} ..."
    local outbound
    outbound=$(_chain_build_outbound "$next_hop_link" "$node_name")

    [ $? -ne 0 ] || [ -z "$outbound" ] && {
        _error "瑙ｆ瀽澶辫触锛岃妫€鏌ラ摼鎺ユ牸寮忋€?
        return 1
    }

    # 鏄剧ず瑙ｆ瀽缁撴灉
    echo ""
    _info "瑙ｆ瀽缁撴灉:"
    echo "$outbound" | jq '{type, server, server_port, tls: .tls.enabled // false, transport: .transport.type // "direct"}'
    echo ""

    read -rp "纭娣诲姞锛焄Y/n]: " confirm
    [[ "$confirm" == "n" || "$confirm" == "N" ]] && { _warn "宸插彇娑堛€?; return 0; }

    # 澶囦唤閰嶇疆
    cp "$CONFIG_FILE" "${CONFIG_FILE}.chain.bak" 2>/dev/null

    # 鍒犻櫎鏃ч摼寮忎唬鐞?outbound锛堣嫢瀛樺湪锛?    _atomic_modify_json "$CONFIG_FILE" "del(.outbounds[] | select(.tag == \"$CHAIN_ROUTE_TAG\"))" 2>/dev/null

    # 娣诲姞鏂?outbound
    _atomic_modify_json "$CONFIG_FILE" ".outbounds += [${outbound}]"

    # 绉婚櫎鏃ч摼寮忚矾鐢辫鍒?    _atomic_modify_json "$CONFIG_FILE" "del(.route.rules[] | select(.outbound == \"$CHAIN_ROUTE_TAG\"))" 2>/dev/null

    # 娣诲姞 AI 璺敱瑙勫垯锛堟彃鍏ュ埌 rule_set 瑙勫垯涔嬪墠锛屽嵆浼樺厛绾ф渶楂橈級
    local rules
    rules=$(_chain_build_rules)
    local rule_array
    rule_array=$(echo "$rules" | jq -c '.')
    _atomic_modify_json "$CONFIG_FILE" ".route.rules = (${rule_array} + .route.rules)"

    # 淇濆瓨鍏冩暟鎹?    local state
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

    # 鏇存柊 Clash YAML锛堝瀛樺湪锛?    if [ -f "${SINGBOX_DIR}/clash.yaml" ] && command -v "$YQ_BINARY" &>/dev/null; then
        _info "鍚屾鍒?Clash YAML..."
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
            # 纭繚鏈夊搴旂殑浠ｇ悊缁?            if ! "$YQ_BIN" eval '.proxy-groups[] | select(.name == "AI閾惧紡")' "$CLASH_YAML" 2>/dev/null | grep -q .; then
                "$YQ_BIN" eval -i '.proxy-groups += [{"name":"AI閾惧紡","type":"select","proxies":["DIRECT"]}]' "$CLASH_YAML" 2>/dev/null
            fi
        fi
    fi

    _success "閾惧紡浠ｇ悊宸叉坊鍔狅紒"
    _success "鑺傜偣鍚嶇О: ${node_name}"
    _success "鍑虹珯鏍囩: ${CHAIN_ROUTE_TAG}"
    echo ""
    _warn "=============================="
    _warn "| 璇烽噸鍚?sing-box 浣块厤缃敓鏁?|"
    _warn "| 鎵ц: sing-box restart     |"
    _warn "=============================="
    echo ""

    read -rp "鏄惁绔嬪嵆閲嶅惎 sing-box锛焄Y/n]: " do_restart
    [[ "$do_restart" != "n" && "$do_restart" != "N" ]] && {
        _info "姝ｅ湪閲嶅惎 sing-box..."
        systemctl restart sing-box 2>/dev/null || rc-service sing-box restart 2>/dev/null || {
            _warn "鏃犳硶鑷姩閲嶅惎锛岃鎵嬪姩閲嶅惎 sing-box銆?
        }
    }
}

# ---- 鏌ョ湅鐘舵€?----
_chain_show_status() {
    _info "========== 閾惧紡浠ｇ悊鐘舵€?=========="
    echo ""

    local state
    state=$(_chain_load_state)

    local enabled
    enabled=$(echo "$state" | jq -r '.enabled // false')
    local current
    current=$(echo "$state" | jq -r '.current // "鏃?')

    echo -e "鐘舵€? $([ "$enabled" == "true" ] && echo -e "${GREEN}宸插惎鐢?{NC}" || echo -e "${RED}宸茬鐢?{NC}")"
    echo -e "褰撳墠鑺傜偣: ${CYAN}${current}${NC}"
    echo ""

    # 妫€鏌ラ厤缃枃浠朵腑鏄惁瀛樺湪閾惧紡 outbound
    if [ -f "$CONFIG_FILE" ]; then
        local has_chain
        has_chain=$(jq -r '.outbounds[] | select(.tag == $tag) | .type' --arg tag "$CHAIN_ROUTE_TAG" "$CONFIG_FILE" 2>/dev/null)
        [ -n "$has_chain" ] && {
            echo "鈹屸攢 Outbound 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€"
            jq '.outbounds[] | select(.tag == $tag)' --arg tag "$CHAIN_ROUTE_TAG" "$CONFIG_FILE" | \
                jq '{绫诲瀷: .type, 鏈嶅姟鍣? .server, 绔彛: .server_port, TLS: (.tls.enabled // false)}'
        }

        local has_rules
        has_rules=$(jq -r '[.route.rules[] | select(.outbound == $tag)] | length' --arg tag "$CHAIN_ROUTE_TAG" "$CONFIG_FILE" 2>/dev/null)
        [ "$has_rules" -gt 0 ] 2>/dev/null && {
            echo "鈹溾攢 Route Rules 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€"
            echo -e "  鍒嗘祦瑙勫垯鏁? ${CYAN}${has_rules}${NC} 鏉?
            echo ""
            echo "  瑕嗙洊鍩熷悕 (鍓?0):"
            jq -r '.route.rules[] | select(.outbound == $tag) | .domain_suffix[]?' --arg tag "$CHAIN_ROUTE_TAG" "$CONFIG_FILE" 2>/dev/null | head -20 | sed 's/^/    /'
        }
        echo "鈹斺攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€"
    else
        _warn "閰嶇疆鏂囦欢 ${CONFIG_FILE} 涓嶅瓨鍦ㄣ€?
    fi
    echo ""

    # 鏄剧ず鍘嗗彶鑺傜偣
    local node_count
    node_count=$(echo "$state" | jq '.nodes | length // 0' 2>/dev/null)
    [ "$node_count" -gt 0 ] 2>/dev/null && {
        echo -e "${CYAN}鍘嗗彶鑺傜偣 (${node_count}):${NC}"
        echo "$state" | jq -r '.nodes | to_entries[] | "  [\(.key)] \(.value.name) 鈥?\(.value.added_at)"' 2>/dev/null
        echo ""
    }
}

# ---- 绠＄悊 AI 鍩熷悕 ----
_chain_manage_domains() {
    while true; do
        echo ""
        _info "========== 绠＄悊鍒嗘祦鍩熷悕 =========="
        echo ""
        echo "褰撳墠 AI 鍩熷悕 (${#_CHAIN_AI_DOMAINS[@]} 涓?:"
        echo "鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€"
        local i=1
        for d in "${_CHAIN_AI_DOMAINS[@]}"; do
            printf "  %2d. %s\n" "$i" "$d"
            ((i++))
        done
        echo "鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€"
        echo ""
        echo "鍏抽敭璇嶅厹搴?(${#_CHAIN_AI_KEYWORDS[@]} 涓?:"
        echo "  ${_CHAIN_AI_KEYWORDS[*]}"
        echo ""
        echo "  1. 娣诲姞鑷畾涔夊煙鍚?
        echo "  2. 鍒犻櫎鍩熷悕"
        echo "  3. 鎭㈠榛樿鍩熷悕鍒楄〃"
        echo "  0. 杩斿洖"
        echo ""
        read -rp "璇烽€夋嫨 [0-3]: " choice

        case "$choice" in
            1)
                read -rp "杈撳叆瑕佽拷鍔犵殑鍩熷悕 (濡?example.com): " new_domain
                [ -z "$new_domain" ] && continue
                _CHAIN_AI_DOMAINS+=("$new_domain")
                _info "宸叉坊鍔? ${new_domain}"
                _info "鈿?淇敼浠呭鏈浼氳瘽鐢熸晥锛屼笅娆¤繍琛岃剼鏈皢鎭㈠榛樿鍒楄〃銆?
                _info "鈿?濡傞渶姘镐箙淇敼锛岃缂栬緫鑴氭湰涓殑 _CHAIN_AI_DOMAINS 鏁扮粍銆?
                ;;
            2)
                read -rp "杈撳叆瑕佸垹闄ょ殑鍩熷悕: " del_domain
                [ -z "$del_domain" ] && continue
                local found=false
                local new_domains=()
                for d in "${_CHAIN_AI_DOMAINS[@]}"; do
                    [ "$d" == "$del_domain" ] && found=true && continue
                    new_domains+=("$d")
                done
                if $found; then
                    _CHAIN_AI_DOMAINS=("${new_domains[@]}")
                    _info "宸插垹闄? ${del_domain}"
                else
                    _warn "鏈壘鍒板煙鍚? ${del_domain}"
                fi
                ;;
            3)
                _info "璇风紪杈戣剼鏈枃浠讹紝灏?_CHAIN_AI_DOMAINS 鏁扮粍鏇挎崲涓洪粯璁ゅ€煎悗閲嶆柊杩愯銆?
                ;;
            0)
                return
                ;;
            *) _warn "鏃犳晥閫夋嫨銆? ;;
        esac
    done
}

# ---- 鍒犻櫎閾惧紡浠ｇ悊 ----
_chain_remove() {
    _info "========== 鍒犻櫎閾惧紡浠ｇ悊 =========="
    echo ""

    local state
    state=$(_chain_load_state)
    local has_chain
    has_chain=$(jq -r '.outbounds[] | select(.tag == $tag) | .type' --arg tag "$CHAIN_ROUTE_TAG" "$CONFIG_FILE" 2>/dev/null)

    if [ -z "$has_chain" ]; then
        _warn "褰撳墠娌℃湁閰嶇疆閾惧紡浠ｇ悊銆?
        return 0
    fi

    echo "灏嗗垹闄や互涓嬪唴瀹?"
    echo "  - outbound: ${CHAIN_ROUTE_TAG}"
    echo "  - 鎵€鏈?AI 鍒嗘祦璺敱瑙勫垯"
    echo ""

    read -rp "纭鍒犻櫎锛熻緭鍏?yes 纭: " confirm
    [ "$confirm" != "yes" ] && { _warn "宸插彇娑堛€?; return 0; }

    cp "$CONFIG_FILE" "${CONFIG_FILE}.chain.bak" 2>/dev/null

    # 鍒犻櫎 outbound
    _atomic_modify_json "$CONFIG_FILE" "del(.outbounds[] | select(.tag == \"$CHAIN_ROUTE_TAG\"))" 2>/dev/null

    # 鍒犻櫎璺敱瑙勫垯
    _atomic_modify_json "$CONFIG_FILE" "del(.route.rules[] | select(.outbound == \"$CHAIN_ROUTE_TAG\"))" 2>/dev/null

    # 鏇存柊鐘舵€佹枃浠?    state=$(echo "$state" | jq '.enabled = false')
    _chain_save_state "$state"

    _success "閾惧紡浠ｇ悊宸插垹闄ゃ€?
    _warn "璇烽噸鍚?sing-box 浣块厤缃敓鏁堛€?
}

# ---- 鍚敤/绂佺敤 ----
_chain_toggle() {
    local state
    state=$(_chain_load_state)
    local enabled
    enabled=$(echo "$state" | jq -r '.enabled // false')

    if [ "$enabled" == "true" ]; then
        _info "褰撳墠鐘舵€? 宸插惎鐢?鈫?绂佺敤涓?.."
        # 绂佺敤锛氫粎绉婚櫎璺敱瑙勫垯锛屼繚鐣?outbound
        cp "$CONFIG_FILE" "${CONFIG_FILE}.chain.bak" 2>/dev/null
        _atomic_modify_json "$CONFIG_FILE" "del(.route.rules[] | select(.outbound == \"$CHAIN_ROUTE_TAG\"))" 2>/dev/null
        state=$(echo "$state" | jq '.enabled = false')
        _chain_save_state "$state"
        _success "閾惧紡浠ｇ悊宸茬鐢紙瑙勫垯宸茬Щ闄わ紝鑺傜偣淇濈暀锛夈€?
    else
        _info "褰撳墠鐘舵€? 宸茬鐢?鈫?鍚敤涓?.."

        # 妫€鏌?outbound 鏄惁瀛樺湪
        local has_outbound
        has_outbound=$(jq -r '.outbounds[] | select(.tag == $tag) | .type' --arg tag "$CHAIN_ROUTE_TAG" "$CONFIG_FILE" 2>/dev/null)
        if [ -z "$has_outbound" ]; then
            _error "鏈壘鍒伴摼寮忎唬鐞嗚妭鐐癸紝璇峰厛娣诲姞鑺傜偣銆?
            return 1
        fi

        cp "$CONFIG_FILE" "${CONFIG_FILE}.chain.bak" 2>/dev/null

        # 鍏堟竻鏃ц鍒?        _atomic_modify_json "$CONFIG_FILE" "del(.route.rules[] | select(.outbound == \"$CHAIN_ROUTE_TAG\"))" 2>/dev/null

        # 閲嶆柊娣诲姞瑙勫垯
        local rules
        rules=$(_chain_build_rules)
        local rule_array
        rule_array=$(echo "$rules" | jq -c '.')
        _atomic_modify_json "$CONFIG_FILE" ".route.rules = (${rule_array} + .route.rules)"

        state=$(echo "$state" | jq '.enabled = true')
        _chain_save_state "$state"
        _success "閾惧紡浠ｇ悊宸插惎鐢ㄣ€?
    fi

    _warn "璇烽噸鍚?sing-box 浣块厤缃敓鏁堛€?
}

# ---- 鏄剧ず璺敱娴嬭瘯淇℃伅 ----
_chain_test_info() {
    _info "========== 璺敱娴嬭瘯 =========="
    echo ""
    echo "閲嶅惎 sing-box 鍚庯紝浣跨敤浠ヤ笅鍛戒护楠岃瘉:"
    echo ""
    echo "  # 娴嬭瘯 Gemini 杩炴帴"
    echo "  curl -x http://127.0.0.1:<HTTP浠ｇ悊绔彛> https://gemini.google.com/ -I"
    echo ""
    echo "  # 娴嬭瘯 OpenAI"
    echo "  curl -x http://127.0.0.1:<HTTP浠ｇ悊绔彛> https://api.openai.com/v1/models -I"
    echo ""
    echo "  # 鏌ョ湅 sing-box 鏃ュ織锛岀‘璁ゆ祦閲忚蛋閾惧紡浠ｇ悊"
    echo "  journalctl -u sing-box -f | grep ${CHAIN_ROUTE_TAG}"
    echo ""
}

# ---- 涓昏彍鍗?----
chain_proxy_menu() {
    _check_root
    while true; do
        echo ""
        echo -e "${CYAN}鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晽${NC}"
        echo -e "${CYAN}鈺?      馃敆 閾惧紡浠ｇ悊绠＄悊 (Chain AI)    鈺?{NC}"
        echo -e "${CYAN}鈺犫晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暎${NC}"
        echo -e "${CYAN}鈺?{NC}  1. 娣诲姞涓嬩竴璺充唬鐞?                 ${CYAN}鈺?{NC}"
        echo -e "${CYAN}鈺?{NC}  2. 鏌ョ湅鐘舵€?& 璺敱璇︽儏             ${CYAN}鈺?{NC}"
        echo -e "${CYAN}鈺?{NC}  3. 绠＄悊鍒嗘祦鍩熷悕                    ${CYAN}鈺?{NC}"
        echo -e "${CYAN}鈺?{NC}  4. 鍚敤 / 绂佺敤閾惧紡浠ｇ悊              ${CYAN}鈺?{NC}"
        echo -e "${CYAN}鈺?{NC}  5. 鍒犻櫎閾惧紡浠ｇ悊                     ${CYAN}鈺?{NC}"
        echo -e "${CYAN}鈺?{NC}  6. 璺敱娴嬭瘯鍛戒护                     ${CYAN}鈺?{NC}"
        echo -e "${CYAN}鈺?{NC}  0. 杩斿洖涓昏彍鍗?                      ${CYAN}鈺?{NC}"
        echo -e "${CYAN}鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暆${NC}"
        echo ""
        read -rp "璇烽€夋嫨 [0-6]: " choice

        case "$choice" in
            1) _chain_add_node ;;
            2) _chain_show_status ;;
            3) _chain_manage_domains ;;
            4) _chain_toggle ;;
            5) _chain_remove ;;
            6) _chain_test_info ;;
            0) return 0 ;;
            *) _warn "璇疯緭鍏?0-6 涔嬮棿鐨勬暟瀛椼€? ;;
        esac
    done
}

# ---- 鐙珛杩愯鍏ュ彛 ----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    chain_proxy_menu "$@"
fi
