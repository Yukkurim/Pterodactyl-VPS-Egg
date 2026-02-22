#!/bin/sh
# ╔══════════════════════════════════════════════════════════════╗
# ║  Linux Distro Installer v2.0                                ║
# ║  日本語対応 / ミラーサーバー対応 / SHA256検証 / 自動リトライ  ║
# ╚══════════════════════════════════════════════════════════════╝

set -eu

. /common.sh

# ──────────────────────────────────────────────────────────────
#  定数 / Constants
# ──────────────────────────────────────────────────────────────
ROOTFS_DIR="/home/container"
DISTRO_MAP_URL="https://distromap.istan.to"
MAX_RETRIES=3
RETRY_DELAY=2
CONNECT_TIMEOUT=10
DOWNLOAD_TIMEOUT=600
LOG_FILE="/tmp/installer.log"

export PATH="$PATH:~/.local/usr/bin"

# ──────────────────────────────────────────────────────────────
#  言語 / Language
# ──────────────────────────────────────────────────────────────
detect_language() {
    for _v in "${LANG:-}" "${LC_ALL:-}" "${LANGUAGE:-}"; do
        case "$_v" in ja*|JA*) echo "ja"; return ;; esac
    done
    echo "en"
}

INSTALLER_LANG="${INSTALLER_LANG:-$(detect_language)}"

msg() {
    eval "_val=\"\${MSG_${INSTALLER_LANG}_${1}:-}\""
    [ -z "$_val" ] && eval "_val=\"\${MSG_en_${1}:-[missing: ${1}]}\""
    printf '%s' "$_val"
}

# ── English ──
MSG_en_CHOOSE_LANG="Select language / 言語を選択してください"
MSG_en_CHOOSE_DISTRO="Please choose your favorite distro:"
MSG_en_ENTER_DISTRO="Enter the desired distro"
MSG_en_ENTER_VERSION="Enter the desired version"
MSG_en_ENTER_MIRROR="Enter mirror number"
MSG_en_GO_BACK="Go Back"
MSG_en_INVALID="Invalid selection. Please try again."
MSG_en_PREPARING="Preparing to install"
MSG_en_SELECTED_VER="Selected version"
MSG_en_DOWNLOADING="Downloading rootfs..."
MSG_en_EXTRACTING="Extracting rootfs..."
MSG_en_CLEANUP="Cleaning up..."
MSG_en_COMPLETE="Installation completed successfully!"
MSG_en_NET_CHECK="Checking network..."
MSG_en_NET_FAIL="Unable to connect. Check your internet."
MSG_en_ARCH_NOSUP="This distro doesn't support your architecture."
MSG_en_FETCH_FAIL="Failed to fetch versions"
MSG_en_DL_FAIL="Failed to download rootfs"
MSG_en_EX_FAIL="Failed to extract rootfs"
MSG_en_VER_FAIL="Failed to determine latest version"
MSG_en_MIR_SELECT="Select a download mirror:"
MSG_en_MIR_AUTO="Auto-detect fastest mirror"
MSG_en_MIR_TESTING="Testing mirror speeds..."
MSG_en_MIR_SELECTED="Selected mirror"
MSG_en_MIR_FALLBACK="Mirror failed, falling back..."
MSG_en_RETRY="Retrying"
MSG_en_HASH_CHECK="Verifying integrity..."
MSG_en_HASH_FAIL="Integrity check failed!"
MSG_en_HASH_OK="Integrity verified."
MSG_en_CONFIRM="Proceed? [Y/n]"
MSG_en_CANCEL="Cancelled."
MSG_en_POST_CFG="Running post-install config..."

# ── Japanese ──
MSG_ja_CHOOSE_LANG="Select language / 言語を選択してください"
MSG_ja_CHOOSE_DISTRO="ディストリビューションを選択してください:"
MSG_ja_ENTER_DISTRO="番号を入力"
MSG_ja_ENTER_VERSION="バージョン番号を入力"
MSG_ja_ENTER_MIRROR="ミラー番号を入力"
MSG_ja_GO_BACK="戻る"
MSG_ja_INVALID="無効な選択です。"
MSG_ja_PREPARING="インストール準備中"
MSG_ja_SELECTED_VER="選択バージョン"
MSG_ja_DOWNLOADING="rootfs をダウンロード中..."
MSG_ja_EXTRACTING="rootfs を展開中..."
MSG_ja_CLEANUP="一時ファイルを削除中..."
MSG_ja_COMPLETE="インストール完了！"
MSG_ja_NET_CHECK="ネットワーク確認中..."
MSG_ja_NET_FAIL="接続できません。回線を確認してください。"
MSG_ja_ARCH_NOSUP="このアーキテクチャには非対応です。"
MSG_ja_FETCH_FAIL="バージョン取得に失敗"
MSG_ja_DL_FAIL="rootfs のダウンロードに失敗"
MSG_ja_EX_FAIL="rootfs の展開に失敗"
MSG_ja_VER_FAIL="最新バージョンの特定に失敗"
MSG_ja_MIR_SELECT="ダウンロードミラーを選択:"
MSG_ja_MIR_AUTO="最速ミラーを自動検出"
MSG_ja_MIR_TESTING="ミラー速度をテスト中..."
MSG_ja_MIR_SELECTED="選択ミラー"
MSG_ja_MIR_FALLBACK="ミラー失敗、フォールバック中..."
MSG_ja_RETRY="リトライ中"
MSG_ja_HASH_CHECK="整合性を検証中..."
MSG_ja_HASH_FAIL="整合性チェック失敗！"
MSG_ja_HASH_OK="整合性確認済。"
MSG_ja_CONFIRM="続行しますか？ [Y/n]"
MSG_ja_CANCEL="キャンセルしました。"
MSG_ja_POST_CFG="インストール後の設定中..."

# ──────────────────────────────────────────────────────────────
#  ミラー定義 / Mirrors
# ──────────────────────────────────────────────────────────────
# id|name|base_url|region|type
#   type: official = /images/ path, tuna = already includes /images/ via base
MIRRORS="
1|Official (Canada)|https://images.linuxcontainers.org|NA|official
2|TUNA (China/Beijing)|https://mirrors.tuna.tsinghua.edu.cn/lxc-images|AS|tuna
3|BFSU (China/Beijing)|https://mirrors.bfsu.edu.cn/lxc-images|AS|tuna
4|USTC (China/Hefei)|https://mirrors.ustc.edu.cn/lxc-images|AS|tuna
5|SJTU (China/Shanghai)|https://mirror.sjtu.edu.cn/lxc-images|AS|tuna
6|SUSTech (China/Shenzhen)|https://mirrors.sustech.edu.cn/lxc-images|AS|tuna
7|Singapore|https://sgp1lxdmirror01.do.letsbuildthe.cloud|AS|official
8|Germany (Frankfurt)|https://fra1lxdmirror01.do.letsbuildthe.cloud|EU|official
9|India (Bangalore)|https://blr1lxdmirror01.do.letsbuildthe.cloud|AS|official
10|Australia (Sydney)|https://syd1lxdmirror01.do.letsbuildthe.cloud|OC|official
11|US (San Francisco)|https://sfo3lxdmirror01.do.letsbuildthe.cloud|NA|official
12|Bulgaria|https://lxd-images.server1.bg|EU|official
13|South Africa|https://za.images.linuxcontainers.org|AF|official
"

MIRROR_COUNT=$(printf '%s\n' "$MIRRORS" | grep -c "^[0-9]")

# ──────────────────────────────────────────────────────────────
#  ディストリ定義 / Distributions
# ──────────────────────────────────────────────────────────────
# number:display:id:flag:post_config:custom_handler:desc_en:desc_ja
distributions="
1:Debian:debian:false:::Stable universal OS:安定・汎用OS
2:Ubuntu:ubuntu:false:::Popular Linux:人気のLinux
3:Void Linux:voidlinux:true:::Rolling-release:ローリングリリース
4:Alpine Linux:alpine:false:::Lightweight:軽量ディストリ
5:CentOS:centos:false:::Enterprise community:企業向けコミュニティ版
6:Rocky Linux:rockylinux:false:::RHEL-compatible:RHEL互換
7:Fedora:fedora:false:::Cutting-edge:最先端
8:AlmaLinux:almalinux:false:::RHEL-compatible:RHEL互換
9:Slackware:slackware:false:::Oldest active distro:最古のディストリ
10:Kali Linux:kali:false:::Pentesting:ペンテスト向け
11:openSUSE:opensuse:false:::Feature-rich:多機能
12:Gentoo:gentoo:true:::Source-based:ソースベース
13:Arch Linux:archlinux:false:archlinux::Rolling-release:ローリングリリース
14:Devuan:devuan:false:::Debian sans systemd:systemdなしDebian
15:Chimera Linux:chimera:custom::chimera_handler:BSD/Linux hybrid:BSD/Linuxハイブリッド
16:Oracle Linux:oracle:false:::Enterprise:エンタープライズ
17:Amazon Linux:amazonlinux:false:::AWS-optimized:AWS最適化
18:Plamo Linux:plamo:false:::JP Slackware-based:日本発Slackware系
19:Linux Mint:mint:false:::User-friendly:初心者向け
20:Alt Linux:alt:false:::Russian distro:ロシア系
21:Funtoo:funtoo:false:::Gentoo-based:Gentoo系
22:openEuler:openeuler:false:::Huawei enterprise:Huawei企業向け
23:Springdale:springdalelinux:false:::Academic RHEL:学術系RHEL互換
"

num_distros=$(printf '%s\n' "$distributions" | grep -c "^[0-9]")

# ──────────────────────────────────────────────────────────────
#  ユーティリティ / Utilities
# ──────────────────────────────────────────────────────────────
log_ts() {
    _ts=$(date '+%H:%M:%S')
    printf "${3:-$NC}[%s] %s${NC}\n" "$_ts" "$2"
    printf "[%s] [%s] %s\n" "$_ts" "$1" "$2" >> "$LOG_FILE" 2>/dev/null || true
}

# cleanup は一度だけ実行
_cleaned=0
cleanup() {
    [ "$_cleaned" = "1" ] && return
    _cleaned=1
    rm -f "$ROOTFS_DIR/rootfs.tar.xz" "$ROOTFS_DIR/rootfs.tar.gz" \
          "/tmp/install_versions.$$" "/tmp/mirror_speed.$$"
    rm -rf /tmp/sbin
}

error_exit() {
    log_ts "ERROR" "$1" "$RED"
    cleanup
    exit 1
}

trap 'printf "\n"; log_ts "INFO" "$(msg CANCEL)" "$YELLOW"; cleanup; exit 130' INT TERM
trap cleanup EXIT

# ──────────────────────────────────────────────────────────────
#  ミラー選択 / Mirror Selection
# ──────────────────────────────────────────────────────────────
SELECTED_MIRROR_URL=""
SELECTED_MIRROR_TYPE=""

get_image_base() {
    # Both types use /images under their base
    echo "${1}/images"
}

# ミラーのn行目を取得 (サブシェル回避)
get_mirror_line() {
    printf '%s\n' "$MIRRORS" | grep "^${1}|"
}

test_mirror_speed() {
    _start=$(date +%s%N 2>/dev/null || date +%s)
    if curl -sf --connect-timeout 5 --max-time 8 -o /dev/null "${1}/images/" 2>/dev/null; then
        _end=$(date +%s%N 2>/dev/null || date +%s)
        if [ ${#_start} -gt 10 ]; then
            echo $(( (_end - _start) / 1000000 ))
        else
            echo $(( (_end - _start) * 1000 ))
        fi
    else
        echo 99999
    fi
}

auto_select_mirror() {
    log_ts "INFO" "$(msg MIR_TESTING)" "$CYAN"
    rm -f "/tmp/mirror_speed.$$"

    _i=1
    while [ "$_i" -le "$MIRROR_COUNT" ]; do
        _ml=$(get_mirror_line "$_i")
        _name=$(echo "$_ml" | cut -d'|' -f2)
        _url=$(echo "$_ml" | cut -d'|' -f3)
        printf "  %-36s ... " "$_name"
        _spd=$(test_mirror_speed "$_url")
        if [ "$_spd" -lt 99999 ]; then
            printf "${GREEN}%sms${NC}\n" "$_spd"
        else
            printf "${RED}timeout${NC}\n"
        fi
        echo "${_i}|${_spd}" >> "/tmp/mirror_speed.$$"
        _i=$((_i + 1))
    done

    _best_id=1
    if [ -f "/tmp/mirror_speed.$$" ]; then
        _best_id=$(sort -t'|' -k2 -n "/tmp/mirror_speed.$$" | head -n1 | cut -d'|' -f1)
        rm -f "/tmp/mirror_speed.$$"
    fi

    _ml=$(get_mirror_line "$_best_id")
    SELECTED_MIRROR_URL=$(echo "$_ml" | cut -d'|' -f3)
    SELECTED_MIRROR_TYPE=$(echo "$_ml" | cut -d'|' -f5)
    printf "\n"
    log_ts "INFO" "$(msg MIR_SELECTED): $(echo "$_ml" | cut -d'|' -f2)" "$GREEN"
}

select_mirror() {
    printf "\n${CYAN}$(msg MIR_SELECT)${NC}\n\n"
    printf "  ${YELLOW}[ 0]${NC} $(msg MIR_AUTO)\n"

    _prev_rgn=""
    _i=1
    while [ "$_i" -le "$MIRROR_COUNT" ]; do
        _ml=$(get_mirror_line "$_i")
        _name=$(echo "$_ml" | cut -d'|' -f2)
        _rgn=$(echo "$_ml" | cut -d'|' -f4)
        if [ "$_rgn" != "$_prev_rgn" ]; then
            case "$_rgn" in
                NA) printf "\n  ${CYAN}── North America ──${NC}\n" ;;
                AS) printf "\n  ${CYAN}── Asia ──${NC}\n" ;;
                EU) printf "\n  ${CYAN}── Europe ──${NC}\n" ;;
                OC) printf "\n  ${CYAN}── Oceania ──${NC}\n" ;;
                AF) printf "\n  ${CYAN}── Africa ──${NC}\n" ;;
            esac
            _prev_rgn="$_rgn"
        fi
        printf "  ${YELLOW}[%2s]${NC} %s\n" "$_i" "$_name"
        _i=$((_i + 1))
    done

    printf "\n${YELLOW}$(msg ENTER_MIRROR) (0-${MIRROR_COUNT}): ${NC}"
    read -r _mc

    if [ -z "$_mc" ] || [ "$_mc" = "0" ]; then
        auto_select_mirror
        return
    fi

    if ! echo "$_mc" | grep -q '^[0-9]*$' || [ "$_mc" -lt 1 ] || [ "$_mc" -gt "$MIRROR_COUNT" ]; then
        log_ts "WARN" "$(msg INVALID)" "$YELLOW"
        _mc=1
    fi

    _ml=$(get_mirror_line "$_mc")
    SELECTED_MIRROR_URL=$(echo "$_ml" | cut -d'|' -f3)
    SELECTED_MIRROR_TYPE=$(echo "$_ml" | cut -d'|' -f5)
    log_ts "INFO" "$(msg MIR_SELECTED): $(echo "$_ml" | cut -d'|' -f2)" "$GREEN"
}

# ──────────────────────────────────────────────────────────────
#  ネットワーク / Network
# ──────────────────────────────────────────────────────────────
check_network() {
    log_ts "INFO" "$(msg NET_CHECK)" "$YELLOW"
    _tu="${SELECTED_MIRROR_URL:-https://images.linuxcontainers.org}"
    if ! curl -sf --connect-timeout "$CONNECT_TIMEOUT" --head "${_tu}/images/" >/dev/null 2>&1; then
        if [ "$_tu" != "https://images.linuxcontainers.org" ]; then
            log_ts "WARN" "$(msg MIR_FALLBACK)" "$YELLOW"
            SELECTED_MIRROR_URL="https://images.linuxcontainers.org"
            SELECTED_MIRROR_TYPE="official"
            if ! curl -sf --connect-timeout "$CONNECT_TIMEOUT" --head "https://images.linuxcontainers.org/images/" >/dev/null 2>&1; then
                error_exit "$(msg NET_FAIL)"
            fi
        else
            error_exit "$(msg NET_FAIL)"
        fi
    fi
}

download_with_retry() {
    _url="$1"; _out="$2"; _att=1
    while [ "$_att" -le "$MAX_RETRIES" ]; do
        [ "$_att" -gt 1 ] && { log_ts "WARN" "$(msg RETRY) (${_att}/${MAX_RETRIES})" "$YELLOW"; sleep "$RETRY_DELAY"; }
        if curl -fL --connect-timeout "$CONNECT_TIMEOUT" --max-time "$DOWNLOAD_TIMEOUT" \
                --progress-bar -o "$_out" "$_url" 2>&1; then
            return 0
        fi
        _att=$((_att + 1))
    done

    # フォールバック: 公式ミラー
    if [ "$SELECTED_MIRROR_URL" != "https://images.linuxcontainers.org" ]; then
        log_ts "WARN" "$(msg MIR_FALLBACK)" "$YELLOW"
        _fb=$(echo "$_url" | sed "s|${SELECTED_MIRROR_URL}|https://images.linuxcontainers.org|")
        _att=1
        while [ "$_att" -le "$MAX_RETRIES" ]; do
            if curl -fL --connect-timeout "$CONNECT_TIMEOUT" --max-time "$DOWNLOAD_TIMEOUT" \
                    --progress-bar -o "$_out" "$_fb" 2>&1; then
                return 0
            fi
            _att=$((_att + 1))
            sleep "$RETRY_DELAY"
        done
    fi
    return 1
}

# ──────────────────────────────────────────────────────────────
#  SHA256検証 / Hash Verification
# ──────────────────────────────────────────────────────────────
verify_hash() {
    [ -z "$2" ] || [ "$2" = "none" ] && return 0
    log_ts "INFO" "$(msg HASH_CHECK)" "$YELLOW"
    if command -v sha256sum >/dev/null 2>&1; then
        _h=$(sha256sum "$1" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
        _h=$(shasum -a 256 "$1" | cut -d' ' -f1)
    else
        return 0
    fi
    if [ "$_h" = "$2" ]; then
        log_ts "INFO" "$(msg HASH_OK)" "$GREEN"; return 0
    else
        log_ts "ERROR" "$(msg HASH_FAIL)" "$RED"
        log_ts "ERROR" "expect: $2" "$RED"
        log_ts "ERROR" "actual: $_h" "$RED"
        return 1
    fi
}

# ──────────────────────────────────────────────────────────────
#  アーキテクチャ / Architecture
# ──────────────────────────────────────────────────────────────
ARCH=$(uname -m)
ARCH_ALT=$(detect_architecture)

# ──────────────────────────────────────────────────────────────
#  バージョンラベル / Version Label
# ──────────────────────────────────────────────────────────────
get_label() {
    _r=$(curl -sf --connect-timeout 5 "$DISTRO_MAP_URL/distro/$1/$2" 2>/dev/null) || { echo "$2"; return; }
    if echo "$_r" | jq -e '.error' >/dev/null 2>&1; then
        echo "$2"
    else
        _l=$(echo "$_r" | jq -r '.label' 2>/dev/null)
        [ -n "$_l" ] && [ "$_l" != "null" ] && echo "$_l" || echo "$2"
    fi
}

# ──────────────────────────────────────────────────────────────
#  ディストリデータ取得 (サブシェル回避)
# ──────────────────────────────────────────────────────────────
get_distro_data() {
    printf '%s\n' "$distributions" | grep "^${1}:"
}

# ──────────────────────────────────────────────────────────────
#  インストール / Installation
# ──────────────────────────────────────────────────────────────
install() {
    _dn="$1"; _pn="$2"; _ic="${3:-false}"
    log_ts "INFO" "$(msg PREPARING) ${_pn}..." "$GREEN"

    _base=$(get_image_base "$SELECTED_MIRROR_URL")
    if [ "$_ic" = "true" ]; then
        _up="${_base}/${_dn}/current/${ARCH_ALT}/"
    else
        _up="${_base}/${_dn}/"
    fi

    _imgs=$(curl -sf --connect-timeout "$CONNECT_TIMEOUT" "$_up" | \
        grep 'href="' | grep -o '"[^/"]*/"' | tr -d '"/' | grep -v '^\.\.$') || \
        error_exit "$(msg FETCH_FAIL) ${_pn}"

    _tf="/tmp/install_versions.$$"
    printf '%s\n' "$_imgs" > "$_tf"
    _vc=$(grep -c . "$_tf")
    [ "$_vc" -eq 0 ] && { rm -f "$_tf"; error_exit "$(msg FETCH_FAIL) ${_pn}"; }

    if [ "$_vc" -eq 1 ]; then
        _ver=1
    else
        printf "\n"
        _c=1
        while IFS= read -r _ln; do
            [ -z "$_ln" ] && continue
            _lb=$(get_label "$_dn" "$_ln")
            printf "  ${YELLOW}[%d]${NC} %s ${CYAN}%s${NC}\n" "$_c" "$_pn" "$_lb"
            _c=$((_c + 1))
        done < "$_tf"
        printf "  ${YELLOW}[0]${NC} $(msg GO_BACK)\n"

        while true; do
            printf "\n${YELLOW}$(msg ENTER_VERSION) (0-${_vc}): ${NC}"
            read -r _ver
            [ "$_ver" = "0" ] && { rm -f "$_tf"; exec "$0"; }
            echo "$_ver" | grep -q '^[0-9]*$' && [ "$_ver" -ge 1 ] && [ "$_ver" -le "$_vc" ] && break
            log_ts "ERROR" "$(msg INVALID)" "$RED"
        done
    fi

    _sv=$(sed -n "${_ver}p" "$_tf")
    rm -f "$_tf"
    _sl=$(get_label "$_dn" "$_sv")
    log_ts "INFO" "$(msg SELECTED_VER): $_sl" "$GREEN"
    download_and_extract "$_dn" "$_sv" "$_ic"
}

install_custom() {
    log_ts "INFO" "$(msg PREPARING) ${1}..." "$GREEN"
    mkdir -p "$ROOTFS_DIR"
    _fn=$(basename "$2")
    log_ts "INFO" "$(msg DOWNLOADING)" "$GREEN"
    download_with_retry "$2" "$ROOTFS_DIR/$_fn" || error_exit "$(msg DL_FAIL)"
    log_ts "INFO" "$(msg EXTRACTING)" "$GREEN"
    tar -xf "$ROOTFS_DIR/$_fn" -C "$ROOTFS_DIR" || error_exit "$(msg EX_FAIL)"
    mkdir -p "$ROOTFS_DIR/home/container/"
    rm -f "$ROOTFS_DIR/$_fn"
}

chimera_handler() {
    _bu="https://repo.chimera-linux.org/live/latest/"
    _lf=$(curl -sf --connect-timeout "$CONNECT_TIMEOUT" "$_bu" | \
        grep -o "chimera-linux-${ARCH}-ROOTFS-[0-9]\{8\}-bootstrap\.tar\.gz" | \
        sort -V | tail -n 1) || error_exit "$(msg FETCH_FAIL) Chimera"
    [ -z "$_lf" ] && error_exit "$(msg FETCH_FAIL) Chimera"
    _d=$(echo "$_lf" | grep -o '[0-9]\{8\}')
    install_custom "Chimera Linux" "${_bu}chimera-linux-${ARCH}-ROOTFS-${_d}-bootstrap.tar.gz"
}

download_and_extract() {
    _dn="$1"; _ver="$2"; _ic="${3:-false}"
    _base=$(get_image_base "$SELECTED_MIRROR_URL")

    if [ "$_ic" = "true" ]; then
        _au="${_base}/${_dn}/current/"
        _url="${_base}/${_dn}/current/${ARCH_ALT}/${_ver}/"
    else
        _au="${_base}/${_dn}/${_ver}/"
        _url="${_base}/${_dn}/${_ver}/${ARCH_ALT}/default/"
    fi

    curl -sf --connect-timeout "$CONNECT_TIMEOUT" "$_au" | grep -q "$ARCH_ALT" || \
        error_exit "$(msg ARCH_NOSUP) ($ARCH_ALT)"

    _lv=$(curl -sf --connect-timeout "$CONNECT_TIMEOUT" "$_url" | \
        grep 'href="' | grep -o '[0-9]\{8\}_[0-9]\{2\}:[0-9]\{2\}/' | \
        sort -r | head -n 1)
    [ -z "$_lv" ] && error_exit "$(msg VER_FAIL)"

    _dl="${_url}${_lv}rootfs.tar.xz"

    # ハッシュ取得
    _eh="none"
    _hr=$(curl -sf --connect-timeout "$CONNECT_TIMEOUT" "${_url}${_lv}SHA256SUMS" 2>/dev/null || true)
    if [ -n "$_hr" ]; then
        _eh=$(echo "$_hr" | grep "rootfs.tar.xz" | awk '{print $1}')
        [ -z "$_eh" ] && _eh="none"
    fi

    log_ts "INFO" "$(msg DOWNLOADING)" "$GREEN"
    mkdir -p "$ROOTFS_DIR"
    download_with_retry "$_dl" "$ROOTFS_DIR/rootfs.tar.xz" || error_exit "$(msg DL_FAIL)"

    if [ "$_eh" != "none" ]; then
        verify_hash "$ROOTFS_DIR/rootfs.tar.xz" "$_eh" || \
            { rm -f "$ROOTFS_DIR/rootfs.tar.xz"; error_exit "$(msg HASH_FAIL)"; }
    fi

    log_ts "INFO" "$(msg EXTRACTING)" "$GREEN"
    tar -xf "$ROOTFS_DIR/rootfs.tar.xz" -C "$ROOTFS_DIR" || error_exit "$(msg EX_FAIL)"
    rm -f "$ROOTFS_DIR/etc/resolv.conf"
    mkdir -p "$ROOTFS_DIR/home/container/"
    rm -f "$ROOTFS_DIR/rootfs.tar.xz"
}

# ──────────────────────────────────────────────────────────────
#  ポストインストール / Post-Install
# ──────────────────────────────────────────────────────────────
post_install_config() {
    log_ts "INFO" "$(msg POST_CFG)" "$GREEN"
    case "$1" in
        archlinux)
            [ -f "$ROOTFS_DIR/etc/pacman.conf" ] && {
                sed -i '/^#RootDir/s/^#//' "$ROOTFS_DIR/etc/pacman.conf"
                sed -i 's|/var/lib/pacman/|/var/lib/pacman|' "$ROOTFS_DIR/etc/pacman.conf"
                sed -i '/^#DBPath/s/^#//' "$ROOTFS_DIR/etc/pacman.conf"
            }
            ;;
    esac
}

# ──────────────────────────────────────────────────────────────
#  メニュー / Menu
# ──────────────────────────────────────────────────────────────
print_banner() {
    printf "${CYAN}"
    cat << 'EOF'

    ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗
    ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝
    ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝
    ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗
    ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗
    ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝
        D I S T R O   I N S T A L L E R  v2

EOF
    printf "${NC}"
}

display_menu() {
    print_banner
    _mirror_host=$(echo "$SELECTED_MIRROR_URL" | sed 's|https\{0,1\}://||;s|/.*||')
    printf "  Arch: ${CYAN}%s${NC} (%s)  Mirror: ${CYAN}%s${NC}\n" "$ARCH" "$ARCH_ALT" "$_mirror_host"
    printf "  ─────────────────────────────────────────\n"
    printf "  ${YELLOW}$(msg CHOOSE_DISTRO)${NC}\n\n"

    _i=1
    while [ "$_i" -le "$num_distros" ]; do
        _dd=$(get_distro_data "$_i")
        [ -z "$_dd" ] && { _i=$((_i + 1)); continue; }
        _dname=$(echo "$_dd" | cut -d: -f2)
        if [ "$INSTALLER_LANG" = "ja" ]; then
            _desc=$(echo "$_dd" | cut -d: -f8)
        else
            _desc=$(echo "$_dd" | cut -d: -f7)
        fi
        if [ -n "$_desc" ]; then
            printf "  ${YELLOW}[%2s]${NC} %-18s ${CYAN}%s${NC}\n" "$_i" "$_dname" "$_desc"
        else
            printf "  ${YELLOW}[%2s]${NC} %s\n" "$_i" "$_dname"
        fi
        _i=$((_i + 1))
    done

    printf "\n  ${YELLOW}$(msg ENTER_DISTRO) (1-${num_distros}): ${NC}"
}

select_language() {
    printf "\n  ${CYAN}$(msg CHOOSE_LANG)${NC}\n\n"
    printf "  ${YELLOW}[1]${NC} English\n"
    printf "  ${YELLOW}[2]${NC} 日本語\n"
    printf "\n  > "
    read -r _lc
    case "$_lc" in 2) INSTALLER_LANG="ja" ;; *) INSTALLER_LANG="en" ;; esac
}

# ══════════════════════════════════════════════════════════════
#  メイン / Main
# ══════════════════════════════════════════════════════════════
: > "$LOG_FILE" 2>/dev/null || true

print_banner
[ -z "${INSTALLER_LANG_OVERRIDE:-}" ] && select_language
select_mirror
check_network
mkdir -p "$ROOTFS_DIR"

if [ "$num_distros" -eq 1 ]; then
    selection=1
else
    display_menu
    read -r selection
    if ! echo "$selection" | grep -q '^[0-9]*$' || \
       [ "$selection" -lt 1 ] || [ "$selection" -gt "$num_distros" ]; then
        error_exit "$(msg INVALID) (1-${num_distros})"
    fi
fi

distro_data=$(get_distro_data "$selection")
[ -z "$distro_data" ] && error_exit "$(msg INVALID) (1-${num_distros})"

display_name=$(echo "$distro_data" | cut -d: -f2)
distro_id=$(echo "$distro_data" | cut -d: -f3)
flag=$(echo "$distro_data" | cut -d: -f4)
post_config=$(echo "$distro_data" | cut -d: -f5)
custom_handler=$(echo "$distro_data" | cut -d: -f6)

# 確認
printf "\n  ┌──────────────────────────────────────┐\n"
printf "  │  %-36s │\n" "${display_name} / ${ARCH_ALT}"
printf "  │  %-36s │\n" "$(echo "$SELECTED_MIRROR_URL" | sed 's|https\{0,1\}://||;s|/.*||')"
printf "  └──────────────────────────────────────┘\n\n"
printf "${YELLOW}$(msg CONFIRM) ${NC}"
read -r _cf
case "$_cf" in [Nn]*) log_ts "INFO" "$(msg CANCEL)" "$YELLOW"; exit 0 ;; esac

# インストール実行
_t0=$(date +%s)

if [ -n "$custom_handler" ]; then
    $custom_handler
else
    install "$distro_id" "$display_name" "$flag"
    [ -n "$post_config" ] && post_install_config "$post_config"
fi

# DNS
[ ! -f "$ROOTFS_DIR/etc/resolv.conf" ] && cat > "$ROOTFS_DIR/etc/resolv.conf" << 'DNSEOF'
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 8.8.8.8
DNSEOF

# 日本語ロケール有効化
if [ "$INSTALLER_LANG" = "ja" ] && [ -f "$ROOTFS_DIR/etc/locale.gen" ]; then
    sed -i 's/^# *\(ja_JP.UTF-8\)/\1/' "$ROOTFS_DIR/etc/locale.gen" 2>/dev/null || true
fi

# ヘルパースクリプトコピー
cp /common.sh /run.sh "$ROOTFS_DIR"
chmod +x "$ROOTFS_DIR/common.sh" "$ROOTFS_DIR/run.sh"
[ -f "/vnc_install.sh" ] && { cp /vnc_install.sh "$ROOTFS_DIR"; chmod +x "$ROOTFS_DIR/vnc_install.sh"; }

# メタデータ保存
_t1=$(date +%s)
_dur=$((_t1 - _t0))
cat > "$ROOTFS_DIR/.install_meta" << METAEOF
DISTRO=${display_name}
DISTRO_ID=${distro_id}
ARCH=${ARCH_ALT}
MIRROR=${SELECTED_MIRROR_URL}
DATE=$(date '+%Y-%m-%d %H:%M:%S')
DURATION=${_dur}s
METAEOF

# 完了表示
if [ "$_dur" -ge 60 ]; then
    _ds="$((_dur / 60))m $((_dur % 60))s"
else
    _ds="${_dur}s"
fi

printf "\n${GREEN}"
printf "  ╔══════════════════════════════════════╗\n"
printf "  ║  %-34s  ║\n" "$(msg COMPLETE)"
printf "  ╠══════════════════════════════════════╣\n"
printf "  ║  Distro: %-25s  ║\n" "$display_name"
printf "  ║  Arch:   %-25s  ║\n" "$ARCH_ALT"
printf "  ║  Time:   %-25s  ║\n" "$_ds"
printf "  ╚══════════════════════════════════════╝\n"
printf "${NC}\n"

log_ts "INFO" "$(msg COMPLETE)" "$GREEN"

