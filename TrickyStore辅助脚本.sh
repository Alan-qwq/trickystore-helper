#!/system/bin/sh
TS_DIR="/data/adb/tricky_store"
TARGET_KEYBOX="$TS_DIR/keybox.xml"
TMP_DIR="/data/local/tmp/keybox_update"
TMP_RAW="$TMP_DIR/raw.tmp"
TMP_KEYBOX="$TMP_DIR/keybox_tmp.xml"

YURIKEY_URL="https://raw.githubusercontent.com/Yurii0307/yurikey/main/key"
TRICKYADDONUPDATETARGETLIST_URL="https://raw.githubusercontent.com/KOWX712/Tricky-Addon-Update-Target-List/keybox/.extra"
INTEGRITYBOX_MIRROR="https://raw.githubusercontent.com/MeowDump/MeowDump/refs/heads/main/NullVoid/OptimusPrime"

CURRENT_VERSION="1.0.0"
UPDATE_JSON_URL="https://raw.githubusercontent.com/Alan-qwq/trickystore-helper/main/update.json"
SCRIPT_PATH=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_decode_progress() {
    local current="$1" total="$2"
    local bar_len=20
    local filled=$((current * bar_len / total))
    local empty=$((bar_len - filled))
    local bar=$(printf "%0.s#" $(seq 1 $filled))$(printf "%0.s-" $(seq 1 $empty))
    echo -ne "${BLUE}[DECODE]${NC} [$bar] $current/$total 层 \r"
    [ "$current" -eq "$total" ] && echo
}

check_root() {
    [ "$(id -u)" -eq 0 ] || { log_error "需要 Root 权限!"; exit 1; }
}

check_tools() {
    local missing=""
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        missing="$missing curl/wget"
    fi
    if ! command -v xxd >/dev/null 2>&1 && ! (command -v toybox >/dev/null 2>&1 && toybox xxd --help >/dev/null 2>&1); then
        missing="$missing xxd"
    fi
    if ! command -v base64 >/dev/null 2>&1 && ! (command -v toybox >/dev/null 2>&1 && toybox base64 --help >/dev/null 2>&1); then
        missing="$missing base64"
    fi
    if [ -n "$missing" ]; then
        log_error "缺少必要工具: $missing"
        exit 1
    fi
}

run_xxd() {
    if command -v xxd >/dev/null 2>&1; then
        xxd "$@"
    elif command -v toybox >/dev/null 2>&1 && toybox xxd --help >/dev/null 2>&1; then
        toybox xxd "$@"
    else
        log_error "系统中未找到 xxd 工具"
        return 1
    fi
}

run_base64_d() {
    if command -v toybox >/dev/null 2>&1; then
        toybox base64 -d "$@"
    else
        base64 -d "$@"
    fi
}

download_file() {
    local url="$1" dest="$2"
    rm -f "$dest"
    local success=1
    if command -v curl >/dev/null 2>&1; then
        curl --connect-timeout 10 --retry 1 -fL --progress-bar "$url" -o "$dest" && success=0
    elif command -v wget >/dev/null 2>&1; then
        wget -T 10 -t 1 --no-check-certificate --progress=bar:force -O "$dest" "$url" && success=0
    else
        log_error "没有可用的下载工具 (curl/wget)"
        return 1
    fi
    if [ $success -eq 0 ] && [ -s "$dest" ]; then
        return 0
    else
        log_error "下载失败或文件为空: $url"
        return 1
    fi
}

init_env() {
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"
    mkdir -p "$TS_DIR"
}

get_script_path() {
    if command -v readlink >/dev/null 2>&1; then
        SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null)
    elif command -v toybox >/dev/null 2>&1; then
        SCRIPT_PATH=$(toybox readlink -f "$0" 2>/dev/null)
    fi
    
    if [ -z "$SCRIPT_PATH" ] || [ ! -f "$SCRIPT_PATH" ]; then
        SCRIPT_PATH="$0"
    fi
    
    if [ ! -w "$SCRIPT_PATH" ]; then
        log_error "脚本文件无写入权限，无法执行更新操作"
        return 1
    fi
    return 0
}

check_update() {
    clear
    sleep 1
    log_info "正在检查更新..."
    if ! get_script_path; then
        return 1
    fi

    local UPDATE_TMP="$TMP_DIR/update.json"
    log_info "正在拉取远程更新配置..."
    if ! download_file "$UPDATE_JSON_URL" "$UPDATE_TMP"; then
        log_error "更新配置文件获取失败，请检查网络连接后重试"
        return 1
    fi

    log_info "正在解析更新信息..."
    local remote_version=$(grep -o '"version": *"[^"]*"' "$UPDATE_TMP" | sed 's/"version": *"//;s/"//g')
    local update_url=$(grep -o '"update_url": *"[^"]*"' "$UPDATE_TMP" | sed 's/"update_url": *"//;s/"//g')
    local update_log=$(grep -o '"update_log": *"[^"]*"' "$UPDATE_TMP" | sed 's/"update_log": *"//;s/"//g')
    local need_update=$(grep -o '"need_update": *[^,}]*' "$UPDATE_TMP" | sed 's/"need_update": *//;s/[ ,}]//g')

    if [ -z "$remote_version" ] || [ -z "$update_url" ]; then
        log_error "更新配置解析失败"
        return 1
    fi

    echo ""
    echo -e "${CYAN}当前版本:${NC} v$CURRENT_VERSION"
    echo -e "${CYAN}最新版本:${NC} v$remote_version"
    echo ""

    local is_need_update=0
    if [ "$need_update" = "true" ]; then
        if [ "$(printf '%s\n%s' "$CURRENT_VERSION" "$remote_version" | sort -V | head -n1)" != "$remote_version" ]; then
            is_need_update=1
        fi
    fi

    if [ $is_need_update -eq 0 ]; then
        log_info "✅ 当前已是最新版本，无需更新"
        return 0
    fi

    echo -e "${YELLOW}===== 发现可用新版本 =====${NC}"
    echo -e "${CYAN}新版本号:${NC} v$remote_version"
    echo -e "${CYAN}更新内容:${NC} $update_log"
    echo -e "${YELLOW}==========================${NC}"
    echo ""

    local update_confirm
    echo -n "是否立即更新到最新版本？[y/n] "
    read update_confirm
    case "$update_confirm" in
        [Yy]*)
            log_info "正在下载新版本安装包..."
            local NEW_SCRIPT_TMP="$TMP_DIR/new_tricky_helper.sh"
            if ! download_file "$update_url" "$NEW_SCRIPT_TMP"; then
                log_error "新版本脚本下载失败，更新已终止"
                return 1
            fi

            if [ ! -s "$NEW_SCRIPT_TMP" ]; then
                log_error "下载的新版本文件为空，更新已终止"
                return 1
            fi

            log_info "正在替换脚本文件..."
            if ! cp -f "$NEW_SCRIPT_TMP" "$SCRIPT_PATH"; then
                log_error "脚本文件替换失败，请检查目录权限"
                return 1
            fi

            chmod 755 "$SCRIPT_PATH"
            if [ $? -ne 0 ]; then
                log_warn "脚本执行权限设置失败"
            fi

            log_info "✅ 脚本更新成功！"
            echo "脚本更新完毕，请重新执行脚本"
            sleep 1
            exit 0
            ;;
        *)
            log_warn "已取消更新，返回主菜单"
            return 0
            ;;
    esac
}

fetch_yurikey() {
    log_info "[1/2] 正在下载 Yurikey 源..."
    if ! download_file "$YURIKEY_URL" "$TMP_RAW"; then
        return 1
    fi
    log_info "[2/2] 正在解码..."
    if ! run_base64_d "$TMP_RAW" > "$TMP_KEYBOX" 2>/dev/null; then
        log_error "解码失败"
        return 1
    fi
    [ -s "$TMP_KEYBOX" ] || { log_error "解码后文件为空"; return 1; }
    return 0
}

fetch_tricky_addon() {
    log_info "[1/2] 正在下载 Tricky Addon-Update Target List 源..."
    if ! download_file "$TRICKYADDONUPDATETARGETLIST_URL" "$TMP_RAW"; then
        return 1
    fi
    log_info "[2/2] 正在解码..."
    if ! cat "$TMP_RAW" | run_xxd -r -p | run_base64_d > "$TMP_KEYBOX" 2>/dev/null; then
        log_error "解码失败"
        return 1
    fi
    [ -s "$TMP_KEYBOX" ] || { log_error "解码后文件为空"; return 1; }
    return 0
}

fetch_integritybox() {
    log_info "[1/3] 正在下载 IntegrityBox 源..."
    if ! download_file "$INTEGRITYBOX_MIRROR" "$TMP_RAW"; then
        return 1
    fi
    cp "$TMP_RAW" "$TMP_DIR/process.tmp"
    log_info "[2/3] 正在解码 (10层Base64)..."
    for i in $(seq 1 10); do
        if [ ! -s "$TMP_DIR/process.tmp" ]; then
            log_error "解码中断：第 $i 层数据为空"
            return 1
        fi
        show_decode_progress $i 10
        if ! run_base64_d "$TMP_DIR/process.tmp" > "$TMP_DIR/process.next" 2>/dev/null; then
            log_error "第 $i 层 Base64 解码失败"
            return 1
        fi
        mv -f "$TMP_DIR/process.next" "$TMP_DIR/process.tmp"
    done
    log_info "[3/3] 正在格式转换..."
    if ! cat "$TMP_DIR/process.tmp" | run_xxd -r -p | tr 'A-Za-z' 'N-ZA-Mn-za-m' > "$TMP_KEYBOX"; then
        log_error "最终格式转换失败"
        return 1
    fi
    [ -s "$TMP_KEYBOX" ] || { log_error "最终文件为空"; return 1; }
    return 0
}

validate_keybox() {
    local file="$1"
    if [ ! -s "$file" ]; then
        log_error "生成的 Keybox 文件无效 (空文件)"
        return 1
    fi
    if ! grep -q "<?xml" "$file" || \
       ! grep -q "<AndroidAttestation>" "$file" || \
       ! grep -q "BEGIN CERTIFICATE" "$file"; then
        log_error "Keybox 内容校验失败"
        return 1
    fi
    local size=$(wc -c < "$file" 2>/dev/null | tr -d ' ')
    log_info "校验通过，文件大小: $size 字节"
    return 0
}

install_keybox() {
    if mv -f "$TMP_KEYBOX" "$TARGET_KEYBOX"; then
        chmod 644 "$TARGET_KEYBOX"
        log_info "✅ Keybox 更新成功！"
        return 0
    else
        log_error "写入文件失败"
        return 1
    fi
}

show_current() {
    if [ -f "$TARGET_KEYBOX" ]; then
        echo -e "${CYAN}当前文件:${NC} $TARGET_KEYBOX"
        ls -lh "$TARGET_KEYBOX"
        echo -e "${CYAN}头部预览:${NC}"
        head -n 5 "$TARGET_KEYBOX"
        echo "..."
    else
        echo -e "${YELLOW}未找到 Keybox 文件${NC}"
    fi
}

keybox_manage_menu() {
    while true; do
        clear
        echo -e "${PURPLE}选择keybox源${NC}"
        echo -e "${GREEN}[1]${NC} Yurikey 源"
        echo -e "${GREEN}[2]${NC} Tricky-Addon-Update-Target-List 源"
        echo -e "${GREEN}[3]${NC} IntegrityBox 源"
        echo -e "${CYAN}[4]${NC} 查看当前Keybox状态"
        echo -e "${RED}[0]${NC} 返回主菜单"
        echo -n "请选择: "
        read sub_choice

        case "$sub_choice" in
            1) fetch_yurikey && validate_keybox "$TMP_KEYBOX" && install_keybox ;;
            2) fetch_tricky_addon && validate_keybox "$TMP_KEYBOX" && install_keybox ;;
            3) fetch_integritybox && validate_keybox "$TMP_KEYBOX" && install_keybox ;;
            4) show_current ;;
            0) return 0 ;;
            *) echo "无效选项" ;;
        esac

        echo ""
        echo -n "按回车继续..."
        read dummy
    done
}

update_target_txt() {
    local target_file="$TS_DIR/target.txt"
    local suffix=""
    local mode_choice

    while true; do
        clear
        echo -e "${CYAN}选择密钥注入模式${NC}"
        echo -e "${GREEN}[1]${NC} 正常模式"
        echo -e "${YELLOW}[2]${NC} 生成证书链（!）"
        echo -e "${YELLOW}[3]${NC} 修改证书链（?）"
        echo -e "${RED}[0]${NC} 退出"
        echo -n "请选择模式: "
        read mode_choice
        case "$mode_choice" in
            1) suffix=""; break ;;
            2) suffix="!"; break ;;
            3) suffix="?"; break ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选项，请重新选择${NC}"; sleep 1 ;;
        esac
    done

    clear
    local SYSTEM_APP=""
    if [ -f "$TS_DIR/system_app" ]; then
        SYSTEM_APP=$(cat "$TS_DIR/system_app" | tr '\n' '|' | sed 's/|*$//')
    fi

    log_info "正在获取应用列表..."
    local pkg_third=$(pm list packages -3 </dev/null 2>&1 | awk -F: '{print $2}' 2>/dev/null)
    local pkg_system=""
    if [ -n "$SYSTEM_APP" ]; then
        pkg_system=$(pm list packages -s </dev/null 2>&1 | awk -F: '{print $2}' | grep -Ex "$SYSTEM_APP" 2>/dev/null || true)
    fi

    local packages=$(printf "%s\n" "$pkg_third" "$pkg_system" | sort -u | grep -v '^$')
    if [ -z "$packages" ]; then
        log_error "未获取到任何非系统应用包名"
        sleep 2
        return 1
    fi

    local app_count=$(echo "$packages" | wc -l)
    log_info "共获取到 $app_count 个应用"
    log_info "正在写入 $target_file ..."
    echo "$packages" | while read -r pkg; do
        [ -n "$pkg" ] && echo "${pkg}${suffix}"
    done > "$target_file"

    if [ $? -eq 0 ] && [ -s "$target_file" ]; then
        local final_count=$(wc -l < "$target_file")
        log_info "✅ target.txt 更新成功！共写入 $final_count 条包名"
        echo -e "${CYAN}文件路径:${NC} $target_file"
        echo -e "${CYAN}内容预览:${NC}"
        head -n 10 "$target_file"
        [ $final_count -gt 10 ] && echo "... 共 $final_count 个应用"
    else
        log_error "写入文件失败，请检查目录权限"
    fi
}

onekey_config_tricky() {
    log_info "[1/3]配置system_app"
    mkdir -p "$TS_DIR"
    if [ ! -f "$TS_DIR/system_app" ]; then
        SYSTEM_APP="com.google.android.gms com.google.android.gsf com.android.vending com.oplus.deepthinker com.heytap.speechassist com.coloros.sceneservice"
        log_info "正在创建system_app文件..."
        touch "$TS_DIR/system_app" || { log_error "创建 system_app 文件失败"; return 1; }
        
        for app in $SYSTEM_APP; do
            if pm list packages -s 2>/dev/null | grep -xq "package:$app"; then
                echo "$app" >> "$TS_DIR/system_app"
                log_info "已添加：$app"
            else
                log_warn "系统中未找到：$app，已跳过"
            fi
        done
        log_info "配置完成"
    else
        log_warn "已存在 system_app 文件，跳过步骤"
    fi

    log_info "[2/3]创建开机prop属性修改脚本"
    local SERVICE_DIR="/data/adb/service.d"
    local PROP_FILE="$SERVICE_DIR/prop_hide.sh"
    mkdir -p "$SERVICE_DIR" || { log_error "创建 service.d 目录失败"; return 1; }

    cat > "$PROP_FILE" <<'EOF'
#!/system/bin/sh

check_reset_prop() {
    local NAME="$1"
    local EXPECTED="$2"
    local VALUE=$(resetprop "$NAME")
    [ -z "$VALUE" ] || [ "$VALUE" = "$EXPECTED" ] || resetprop -n "$NAME" "$EXPECTED"
}

contains_reset_prop() {
    local NAME="$1"
    local CONTAINS="$2"
    local NEWVAL="$3"
    local VALUE=$(resetprop "$NAME")
    case "$VALUE" in
        *"$CONTAINS"*) resetprop -n "$NAME" "$NEWVAL" ;;
    esac
}

empty_reset_prop() {
    local NAME="$1"
    local NEWVAL="$2"
    local VALUE=$(getprop "$NAME")
    [ -z "$VALUE" ] && resetprop -n "$NAME" "$NEWVAL"
}

resetprop -w sys.boot_completed 0

if [ -f "/data/adb/boot_hash" ]; then
    hash_value=$(grep -v '^#' "/data/adb/boot_hash" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if [ -n "$hash_value" ]; then
        resetprop -n ro.boot.vbmeta.digest "$hash_value"
    else
        rm -f /data/adb/boot_hash
    fi
fi
empty_reset_prop "ro.boot.vbmeta.invalidate_on_error" "yes"
empty_reset_prop "ro.boot.vbmeta.avb_version" "1.0"
empty_reset_prop "ro.boot.vbmeta.hash_alg" "sha256"
empty_reset_prop "ro.boot.vbmeta.size" "4096"

check_reset_prop "ro.boot.vbmeta.device_state" "locked"
check_reset_prop "ro.boot.verifiedbootstate" "green"
check_reset_prop "ro.boot.flash.locked" "1"
check_reset_prop "ro.boot.veritymode" "enforcing"
check_reset_prop "ro.boot.warranty_bit" "0"
check_reset_prop "ro.warranty_bit" "0"
check_reset_prop "ro.debuggable" "0"
check_reset_prop "ro.force.debuggable" "0"
check_reset_prop "ro.secure" "1"
check_reset_prop "ro.adb.secure" "1"
check_reset_prop "ro.build.type" "user"
check_reset_prop "ro.build.tags" "release-keys"
check_reset_prop "ro.vendor.boot.warranty_bit" "0"
check_reset_prop "ro.vendor.warranty_bit" "0"
check_reset_prop "vendor.boot.vbmeta.device_state" "locked"
check_reset_prop "vendor.boot.verifiedbootstate" "green"
check_reset_prop "sys.oem_unlock_allowed" "0"

check_reset_prop "ro.secureboot.lockstate" "locked"
check_reset_prop "ro.boot.realmebootstate" "green"
check_reset_prop "ro.boot.realme.lockstate" "1"
contains_reset_prop "ro.bootmode" "recovery" "unknown"
contains_reset_prop "ro.boot.bootmode" "recovery" "unknown"
contains_reset_prop "vendor.boot.bootmode" "recovery" "unknown"
EOF

    chmod 755 "$PROP_FILE" || { log_error "设置 prop_hide.sh 执行权限失败"; return 1; }
    if [ -s "$PROP_FILE" ]; then
        log_info "prop_hide.sh 脚本创建成功，路径：$PROP_FILE"
        log_info "已设置开机自动执行权限，重启后生效"
    else
        log_error "prop_hide.sh 写入失败，文件为空"
        return 1
    fi

log_info "5秒后进行下一步..."
sleep 5
clear
reset
log_info "[3/3]执行一键更新target.txt"
update_target_txt || { log_error "target.txt 更新失败"; return 1; }

    log_info "✅一键配置TrickyStore已完成！"
    return 0
}

cleanup() {
    rm -rf "$TMP_DIR"
    log_info "临时文件已清理"
}

main() {
    check_root
    check_tools
    init_env
    trap cleanup EXIT INT TERM

    while true; do
        clear
        echo -e "${PURPLE}TrickyStore辅助脚本 v1.0.0 20260321
by 酷安 ALAN_233${NC}"
        echo -e "${GREEN}[1]${NC} 一键更新有效密钥"
        echo -e "${CYAN}[2]${NC} 一键更新 target.txt"
        echo -e "${PURPLE}[3]${NC} 一键配置 TrickyStore"
        echo -e "${BLUE}[4]${NC} 查看作者酷安"
        echo -e "${BLUE}[5]${NC} 检查更新"
        echo -e "${RED}[0]${NC} 退出"
        echo -n "请选择: "
        read choice

        case "$choice" in
            1) keybox_manage_menu ;;
            2) update_target_txt ;;
            3) 
                clear
                echo -e "${YELLOW}【操作确认】${NC}"
                echo -e "本操作用于配置TrickyStore和完成部分环境隐藏
使用本脚本无需安装任何TrickyStore的辅助模块（如Tricky-Addon-Update-Target-List等），否则可能导致冲突
重启即可完成隐藏"
                echo -e "此操作将执行以下3个步骤："
                echo -e "1. 配置/data/adb/tricky_store/system_app"
                echo -e "2. 创建开机自动执行的prop属性修改脚本"
                echo -e "3. 执行一键更新 target.txt"
                echo -n "是否确认继续？[y/n] "
                read confirm
                case "$confirm" in
                    [Yy]*) 
                        onekey_config_tricky
                        ;;
                    *)
                        log_warn "用户取消操作，返回菜单"
                        ;;
                esac
            ;;
            4) log_info "正在跳转作者酷安主页..." && am start -a android.intent.action.VIEW -d "https://www.coolapk.com/u/38346436" 2>/dev/null || log_error "跳转失败，请手动访问：https://www.coolapk.com/u/38346436" ;;
            5) check_update ;;
            0) exit 0 ;;
            *) echo "无效选项" ;;
        esac

        echo ""
        echo -n "按回车继续..."
        read dummy
    done
}

main
