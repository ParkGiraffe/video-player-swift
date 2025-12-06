#!/usr/bin/env bash

# MPV 및 의존성 라이브러리를 앱 번들에 포함시키는 스크립트
# 사용법: ./bundle-dylibs.sh /path/to/YourApp.app

set -e

APP_PATH="$1"

if [ -z "$APP_PATH" ]; then
    echo "Usage: $0 /path/to/YourApp.app"
    exit 1
fi

FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/VideoPlayer"

# Frameworks 폴더 생성
mkdir -p "$FRAMEWORKS_DIR"

echo "🔍 Collecting MPV and dependencies..."

# 처리된 라이브러리를 저장할 임시 파일 (name -> path 매핑)
PROCESSED_FILE=$(mktemp)
QUEUE_FILE=$(mktemp)
PATHS_FILE=$(mktemp)

trap "rm -f $PROCESSED_FILE $QUEUE_FILE $PATHS_FILE" EXIT

# 초기 라이브러리
echo "/opt/homebrew/opt/mpv/lib/libmpv.2.dylib" > "$QUEUE_FILE"

# 재귀적으로 모든 의존성 찾기
echo "📚 Scanning dependencies..."

while [ -s "$QUEUE_FILE" ]; do
    # 큐에서 첫 번째 항목 가져오기
    lib=$(head -1 "$QUEUE_FILE")
    tail -n +2 "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" && mv "${QUEUE_FILE}.tmp" "$QUEUE_FILE"
    
    # 심볼릭 링크인 경우 실제 파일 찾기
    if [ -L "$lib" ]; then
        real_lib=$(readlink "$lib")
        # 상대 경로인 경우 절대 경로로 변환
        if [[ ! "$real_lib" = /* ]]; then
            real_lib="$(dirname "$lib")/$real_lib"
        fi
        lib="$real_lib"
    fi
    
    basename_lib=$(basename "$lib")
    
    # 이미 처리된 라이브러리인지 확인
    if grep -q "^${basename_lib}$" "$PROCESSED_FILE" 2>/dev/null; then
        continue
    fi
    
    # 시스템 라이브러리는 건너뛰기
    if [[ "$lib" == /System/* ]] || [[ "$lib" == /usr/lib/* ]]; then
        continue
    fi
    
    # 실제 파일인지 확인
    if [ ! -f "$lib" ]; then
        continue
    fi
    
    echo "$basename_lib" >> "$PROCESSED_FILE"
    echo "$lib" >> "$PATHS_FILE"
    echo "  📦 $basename_lib"
    
    # 의존성 찾기
    deps=$(otool -L "$lib" 2>/dev/null | tail -n +2 | awk '{print $1}' || true)
    
    for dep in $deps; do
        resolved_dep=""
        
        # Homebrew 라이브러리
        if [[ "$dep" == /opt/homebrew/* ]]; then
            resolved_dep="$dep"
        # @rpath 의존성 - Homebrew에서 찾기
        elif [[ "$dep" == @rpath/* ]]; then
            dep_name=$(basename "$dep")
            # Homebrew lib 폴더에서 찾기 (파일 또는 symlink)
            found_dep=$(find /opt/homebrew/lib /opt/homebrew/opt -name "$dep_name" \( -type f -o -type l \) 2>/dev/null | head -1)
            if [ -n "$found_dep" ]; then
                resolved_dep="$found_dep"
            fi
        fi
        
        if [ -n "$resolved_dep" ]; then
            # 심볼릭 링크 처리
            if [ -L "$resolved_dep" ]; then
                real_dep=$(readlink "$resolved_dep")
                if [[ ! "$real_dep" = /* ]]; then
                    real_dep="$(dirname "$resolved_dep")/$real_dep"
                fi
                resolved_dep="$real_dep"
            fi
            if [ -f "$resolved_dep" ]; then
                echo "$resolved_dep" >> "$QUEUE_FILE"
            fi
        fi
    done
done

TOTAL=$(wc -l < "$PROCESSED_FILE" | tr -d ' ')
echo ""
echo "📋 Found $TOTAL libraries to bundle"
echo ""

# 라이브러리 복사 (원본 경로 사용)
echo "📥 Copying libraries to Frameworks..."
while IFS= read -r lib_path; do
    if [ -f "$lib_path" ]; then
        lib_name=$(basename "$lib_path")
        cp -f "$lib_path" "$FRAMEWORKS_DIR/"
        echo "  ✅ $lib_name"
        
        # 원본 위치의 심볼릭 링크들도 복사
        lib_dir=$(dirname "$lib_path")
        for symlink in "$lib_dir"/*.dylib; do
            if [ -L "$symlink" ]; then
                symlink_target=$(readlink "$symlink")
                if [ "$symlink_target" = "$lib_name" ] || [ "$symlink_target" = "./$lib_name" ]; then
                    symlink_name=$(basename "$symlink")
                    if [ ! -e "$FRAMEWORKS_DIR/$symlink_name" ]; then
                        ln -sf "$lib_name" "$FRAMEWORKS_DIR/$symlink_name"
                        echo "    🔗 $symlink_name -> $lib_name"
                    fi
                fi
            fi
        done
    fi
done < "$PATHS_FILE"

echo ""
echo "🔧 Fixing library paths..."

# 모든 라이브러리 경로 수정
for dylib in "$FRAMEWORKS_DIR"/*.dylib; do
    if [ -f "$dylib" ]; then
        dylib_name=$(basename "$dylib")
        
        # install_name 변경
        install_name_tool -id "@rpath/$dylib_name" "$dylib" 2>/dev/null || true
        
        # 의존성 경로 변경
        deps=$(otool -L "$dylib" 2>/dev/null | tail -n +2 | awk '{print $1}' || true)
        
        for dep in $deps; do
            if [[ "$dep" == /opt/homebrew/* ]]; then
                dep_name=$(basename "$dep")
                install_name_tool -change "$dep" "@rpath/$dep_name" "$dylib" 2>/dev/null || true
            fi
        done
    fi
done

# 실행 파일 경로 수정
echo "🔧 Fixing executable paths..."
if [ -f "$EXECUTABLE_PATH" ]; then
    # 기존 rpath 제거 (에러 무시)
    install_name_tool -delete_rpath "@executable_path/../Frameworks" "$EXECUTABLE_PATH" 2>/dev/null || true
    
    # rpath 추가
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXECUTABLE_PATH" 2>/dev/null || true
    
    # libmpv 경로 변경
    install_name_tool -change "/opt/homebrew/opt/mpv/lib/libmpv.2.dylib" "@rpath/libmpv.2.dylib" "$EXECUTABLE_PATH" 2>/dev/null || true
    
    # 다른 Homebrew 라이브러리 경로도 변경
    deps=$(otool -L "$EXECUTABLE_PATH" 2>/dev/null | tail -n +2 | awk '{print $1}' || true)
    for dep in $deps; do
        if [[ "$dep" == /opt/homebrew/* ]]; then
            dep_name=$(basename "$dep")
            install_name_tool -change "$dep" "@rpath/$dep_name" "$EXECUTABLE_PATH" 2>/dev/null || true
        fi
    done
fi

echo ""
echo "🔗 Creating symlinks for required libraries..."
# 번들 내 라이브러리들이 요구하는 @rpath 의존성에 대한 심볼릭 링크 생성
for dylib in "$FRAMEWORKS_DIR"/*.dylib; do
    if [ -f "$dylib" ]; then
        deps=$(otool -L "$dylib" 2>/dev/null | grep "@rpath" | awk '{print $1}' | sed 's/@rpath\///' || true)
        for dep in $deps; do
            # 해당 파일이 없고, 유사한 이름의 파일이 있으면 심볼릭 링크 생성
            if [ ! -e "$FRAMEWORKS_DIR/$dep" ]; then
                # 패턴 매칭으로 대상 찾기
                base_name=$(echo "$dep" | sed 's/\.dylib$//')
                matched_file=$(ls "$FRAMEWORKS_DIR" 2>/dev/null | grep "^${base_name}" | grep "\.dylib$" | head -1)
                if [ -n "$matched_file" ] && [ -f "$FRAMEWORKS_DIR/$matched_file" ]; then
                    ln -sf "$matched_file" "$FRAMEWORKS_DIR/$dep"
                    echo "  🔗 $dep -> $matched_file"
                fi
            fi
        done
    fi
done

# 추가 패턴 심볼릭 링크 (버전 형식 정규화)
for dylib in "$FRAMEWORKS_DIR"/*.dylib; do
    if [ -f "$dylib" ]; then
        dylib_name=$(basename "$dylib")
        # 패턴: libXXX.N.M.P.dylib -> libXXX.N.dylib
        if [[ "$dylib_name" =~ ^(lib[a-zA-Z0-9_+-]+\.[0-9]+)\.[0-9]+\.[0-9]+\.dylib$ ]]; then
            short_name="${BASH_REMATCH[1]}.dylib"
            if [ ! -e "$FRAMEWORKS_DIR/$short_name" ]; then
                ln -sf "$dylib_name" "$FRAMEWORKS_DIR/$short_name"
                echo "  🔗 $short_name -> $dylib_name"
            fi
        fi
    fi
done

echo ""
echo "🔐 Signing libraries..."
for dylib in "$FRAMEWORKS_DIR"/*.dylib; do
    if [ -f "$dylib" ]; then
        codesign --force --sign - "$dylib" 2>/dev/null || true
    fi
done

echo ""
echo "✅ Done! Libraries bundled successfully."
echo ""
echo "📊 Summary:"
echo "   - Libraries bundled: $TOTAL"
echo "   - Location: $FRAMEWORKS_DIR"

# 전체 크기 표시
TOTAL_SIZE=$(du -sh "$FRAMEWORKS_DIR" 2>/dev/null | awk '{print $1}')
echo "   - Total size: $TOTAL_SIZE"
