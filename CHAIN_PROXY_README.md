# 閾惧紡浠ｇ悊妯″潡 - 閮ㄧ讲璇存槑

## 鏂囦欢

- `chain_proxy.sh` 鈥?閾惧紡浠ｇ悊鐙珛妯″潡锛屽彲鍗曠嫭杩愯涔熷彲琚?singbox.sh 璋冪敤

## 閮ㄧ讲姝ラ

### 1. 涓婁紶鏂囦欢鍒?VPS

```bash
# 灏?chain_proxy.sh 涓婁紶鍒颁笌 singbox.sh 鍚岀骇鐩綍
scp chain_proxy.sh root@<VPS_IP>:/root/
# 鎴栧湪 VPS 涓婄洿鎺ヤ笅杞?curl -O https://raw.githubusercontent.com/<浣犵殑fork>/singbox-lite/main/chain_proxy.sh
```

### 2. 璧嬩簣鎵ц鏉冮檺

```bash
chmod +x /root/chain_proxy.sh
```

### 3. 闆嗘垚鍒?singbox.sh 涓昏彍鍗?
缂栬緫 `singbox.sh`锛屾壘鍒般€岃繘闃跺姛鑳姐€嶈彍鍗曞尯鍩燂紝娣诲姞绗?19 椤广€?
**鏌ユ壘浣嶇疆鐨勭嚎绱?*锛堝湪 singbox.sh 涓悳绱級锛?```
grep -n "杩涢樁鍔熻兘\|19\|\"18\"" singbox.sh
```

**娣诲姞浣嶇疆**锛氬湪銆岃繘闃跺姛鑳姐€嶈彍鍗曠殑 case 鍒嗘敮涓紝鏈€鍚庝竴涓€夐」锛堥€氬父鏄?`18)` 鎴栫被浼硷級涔嬪悗銆乣0)` 杩斿洖涔嬪墠锛屾坊鍔狅細

```bash
# 鍦?"echo" 鎵撳嵃鑿滃崟鍖哄煙娣诲姞涓€琛岋細
echo -e "${CYAN}鈺?{NC} 19. 閾惧紡浠ｇ悊 鈥?AI 娴侀噺鍒嗘祦               ${CYAN}鈺?{NC}"

# 鍦?case "$choice" 鍖哄煙娣诲姞锛?19)
    bash "$SCRIPT_DIR/chain_proxy.sh"
    ;;
```

**鍏蜂綋娣诲姞绀轰緥**锛堝亣璁惧綋鍓嶆渶澶х紪鍙锋槸 18锛夛細

```bash
# 1. 鎵惧埌鑿滃崟鎵撳嵃鍖哄煙锛堜竴鍫?echo 琛岋級锛屽湪鏈€鍚庡姞鍏ワ細
#    echo -e "${CYAN}鈺?{NC} 19. 閾惧紡浠ｇ悊 鈥?AI 娴侀噺鍒嗘祦               ${CYAN}鈺?{NC}"

# 2. 鎵惧埌 case 鍒嗘敮锛屽湪 ;; 鍜?0) 涔嬮棿鍔犲叆:
            19)
                bash "$SCRIPT_DIR/chain_proxy.sh"
                ;;
```

### 4. 閲嶅惎鑴氭湰

```bash
./singbox.sh
# 杩涘叆杩涢樁鍔熻兘 鈫?閫夋嫨 19 閾惧紡浠ｇ悊
```

---

## 鐙珛杩愯

```bash
./chain_proxy.sh
```

---

## 鍔熻兘娓呭崟

| 閫夐」 | 鍔熻兘 |
|------|------|
| 1. 娣诲姞涓嬩竴璺充唬鐞?| 绮樿创 ss:// vless:// vmess:// trojan:// hy2:// socks5:// 閾炬帴 |
| 2. 鏌ョ湅鐘舵€?| 鏄剧ず褰撳墠 outbound銆佽矾鐢辫鍒欐暟銆佽鐩栧煙鍚嶅垪琛?|
| 3. 绠＄悊鍒嗘祦鍩熷悕 | 杩藉姞/鍒犻櫎鑷畾涔夊煙鍚嶏紙鏈浼氳瘽鏈夋晥锛?|
| 4. 鍚敤/绂佺敤 | 涓€閿紑鍏筹紝浠呯Щ闄よ矾鐢辫鍒欙紝鑺傜偣淇濈暀 |
| 5. 鍒犻櫎閾惧紡浠ｇ悊 | 瀹屽叏娓呴櫎 outbound + 璺敱瑙勫垯 |
| 6. 璺敱娴嬭瘯鍛戒护 | 鏄剧ず curl 娴嬭瘯鍜屾棩蹇楄繃婊ゅ懡浠?|

---

## 宸ヤ綔娴佺▼

```
鐢ㄦ埛绮樿创涓嬩竴璺抽摼鎺?       鈫?parser.sh 瑙ｆ瀽涓?sing-box outbound
       鈫?鍐欏叆 config.json (outbounds)
       鈫?娉ㄥ叆 route.rules锛圓I 鍩熷悕 鈫?chain-ai锛?       鈫?閲嶅惎 sing-box 鐢熸晥
```

## Sing-box 閰嶇疆缁撴瀯

```jsonc
// 鏂板鐨?outbound
{
  "tag": "chain-ai",
  "type": "shadowsocks",        // 鏍规嵁閾炬帴鑷姩妫€娴?  "server": "1.2.3.4",
  "server_port": 8388,
  "method": "2022-blake3-aes-256-gcm",
  "password": "xxx",
  "detour": "direct-out"       // 鐩磋繛涓嬩竴璺筹紝閬垮厤閫掑綊
}

// 鏂板鐨?route rules锛堟彃鍏ュ埌 rules 鏁扮粍鏈€鍓嶉潰锛屼紭鍏堢骇鏈€楂橈級
[
  {"domain_suffix": ["google.com"], "outbound": "chain-ai"},
  {"domain_suffix": ["googleapis.com"], "outbound": "chain-ai"},
  // ... 40+ AI 鍩熷悕 ...
  {"domain_keyword": ["gemini", "generativelanguage", ...], "outbound": "chain-ai"}
]
```

## 婵€杩涚増 AI 鍩熷悕瑕嗙洊

### 鍏ㄥ悗缂€瑕嗙洊
- Google 鍏ㄥ妗跺叏瀛愬煙: google.com, googleapis.com, gstatic.com, googleusercontent.com, 1e100.net
- Android GMS/Firebase: firebaseio.com, firebaseapp.com, app-measurement.com, gvt2.com, gvt3.com
- OpenAI: openai.com, chatgpt.com, oaistatic.com, sora.com
- Anthropic: anthropic.com, claude.ai
- Google AI: deepmind.com, bard.google.com, aistudio.google.com, ai.google.dev, makersuite.google.com
- 鍏朵粬 AI: perplexity.ai, groq.com, deepseek.com, openrouter.ai, cohere.com, together.ai, mistral.ai, x.ai, poe.com, you.com, phind.com, character.ai
- AI 缂栫▼: githubcopilot.com, cursor.sh, windsurf.com, codeium.com, tabnine.com, sourcegraph.com

### 鍏抽敭璇嶅厹搴?gemini, generativelanguage, alkalimakersuite, proactiveagent, deepmind, bard, notebooklm, colab

---

## 娉ㄦ剰浜嬮」

1. **蹇呴』鍏堝畨瑁呭ソ sing-box** 骞跺凡鏈?config.json
2. **parser.sh 蹇呴』瀛樺湪** 浜庡悓鐩綍锛坈hain_proxy.sh 浼氳皟鐢ㄥ畠瑙ｆ瀽閾炬帴锛?3. **閲嶅惎 sing-box 鍚庢墠鐢熸晥**锛堣剼鏈細璇㈤棶鏄惁鑷姩閲嶅惎锛?4. **澶囦唤鑷姩鐢熸垚** `config.json.chain.bak`
5. **閲嶅惎鍚庤鍒欐彃鍏ュ埌 rules 鏈€鍓嶉潰**锛屼紭鍏堢骇楂樹簬鍏朵粬璺敱瑙勫垯
