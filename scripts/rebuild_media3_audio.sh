#!/usr/bin/env bash
set -euo pipefail

# Rebuild only the native audio libraries; preserve the pinned Media3 Java API.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NDK="${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to an installed Android NDK}"
HOST="${NDK_HOST_TAG:-darwin-x86_64}"
TOOLS="$NDK/toolchains/llvm/prebuilt/$HOST/bin"
WORK="${1:?Usage: rebuild_media3_audio.sh work-directory [output.aar]}"
OUTPUT="${2:-$WORK/media3-decoder-ffmpeg-1.10.1.aar}"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
mkdir -p "$(dirname "$OUTPUT")"
OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
FFMPEG=3f92512fd1fd6f5e6d6eb45a156c352835314d69
MEDIA3=5fb306449733dd71595700c1227ad6087578c559
if [[ ! -f "$WORK/source.tar.gz" ]]; then
  curl --fail --location --retry 3 "https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/$FFMPEG" -o "$WORK/source.tar.gz"
fi
[[ "$(shasum -a 256 "$WORK/source.tar.gz")" == "6b1878387ad04ba735fadfee85a65f6118548cfb817f13129a6184febab42916  "* ]] || exit 1
mkdir -p "$WORK/ffmpeg"
tar -xzf "$WORK/source.tar.gz" --strip-components=1 -C "$WORK/ffmpeg"
curl --fail --location --retry 3 "https://raw.githubusercontent.com/androidx/media/$MEDIA3/libraries/decoder_ffmpeg/src/main/jni/ffmpeg_jni.cc" -o "$WORK/ffmpeg_jni.cc"
[[ "$(shasum -a 256 "$WORK/ffmpeg_jni.cc")" == "cebafb59c70cd7082d40a94d33680f8627547994758fbd8551ab4b3434d4088c  "* ]] || exit 1
mkdir -p "$WORK/aar"
unzip -qo "$ROOT/android/app/libs/media3-decoder-ffmpeg-1.10.1.aar" -d "$WORK/aar"
for ABI in armeabi-v7a arm64-v8a; do
  if [[ "$ABI" == armeabi-v7a ]]; then
    ARCH=arm
    TARGET=armv7a-linux-androideabi
    LINK_FLAGS=()
  else
    ARCH=aarch64
    TARGET=aarch64-linux-android
    # Matches Media3's CMake workaround for AArch64 assembly relocations.
    LINK_FLAGS=(-Wl,-Bsymbolic)
  fi
  mkdir -p "$WORK/$ABI"
  (
    cd "$WORK/$ABI"
    "$WORK/ffmpeg/configure" --target-os=android --arch="$ARCH" \
      --enable-cross-compile --cc="$TOOLS/${TARGET}23-clang" \
      --ar="$TOOLS/llvm-ar" --nm="$TOOLS/llvm-nm" --ranlib="$TOOLS/llvm-ranlib" \
      --strip="$TOOLS/llvm-strip" --enable-pic --enable-static --disable-shared \
      --disable-doc --disable-programs --disable-everything --disable-avdevice \
      --disable-avformat --disable-swscale --disable-postproc --disable-avfilter \
      --disable-symver --disable-v4l2-m2m --disable-vulkan --enable-swresample \
      --enable-decoder=ac3,eac3,mlp,truehd,dca,mp1,mp2,mp3 \
      --extra-cflags=-fPIC
    make -j"${JOBS:-4}"
    "$TOOLS/${TARGET}23-clang++" -shared -fPIC -O2 -std=c++17 \
      -I. -I"$WORK/ffmpeg" "$WORK/ffmpeg_jni.cc" \
      -Wl,--start-group libavcodec/libavcodec.a libswresample/libswresample.a libavutil/libavutil.a \
      -Wl,--end-group -Wl,-z,max-page-size=16384 -Wl,-soname,libffmpegJNI.so \
      ${LINK_FLAGS[@]+"${LINK_FLAGS[@]}"} -static-libstdc++ -llog -lm -lz -o "$WORK/aar/jni/$ABI/libffmpegJNI.so"
    "$TOOLS/llvm-strip" --strip-unneeded "$WORK/aar/jni/$ABI/libffmpegJNI.so"
    "$TOOLS/llvm-nm" -D "$WORK/aar/jni/$ABI/libffmpegJNI.so" | rg 'ff_mp3_decoder'
  )
done
(cd "$WORK/aar" && zip -qr "$OUTPUT" .)
shasum -a 256 "$OUTPUT"
