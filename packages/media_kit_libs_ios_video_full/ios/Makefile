all: Frameworks/*.xcframework Frameworks/.symlinks

MPV_XCFRAMEWORKS_VERSION=v0.6.0
MPV_XCFRAMEWORKS_SHA256SUM=652047297624170bfd172ef25a99e49603c032d189a1761335edcb36db55b7ee

.cache/xcframeworks/libmpv-xcframeworks-${MPV_XCFRAMEWORKS_VERSION}-ios-universal.tar.gz:
	mkdir -p .cache/xcframeworks
	rm -f .cache/xcframeworks/*.tmp .cache/xcframeworks/*-ios-universal.tar.gz
	curl -fL \
		https://github.com/media-kit/libmpv-darwin-build/releases/download/${MPV_XCFRAMEWORKS_VERSION}/libmpv-xcframeworks_${MPV_XCFRAMEWORKS_VERSION}_ios-universal-video-full.tar.gz \
		-o .cache/xcframeworks/libmpv.tar.gz.tmp
	printf '%s  %s\n' '${MPV_XCFRAMEWORKS_SHA256SUM}' '.cache/xcframeworks/libmpv.tar.gz.tmp' | shasum -a 256 -c
	mv .cache/xcframeworks/libmpv.tar.gz.tmp .cache/xcframeworks/libmpv-xcframeworks-${MPV_XCFRAMEWORKS_VERSION}-ios-universal.tar.gz
	touch .cache/xcframeworks/libmpv-xcframeworks-${MPV_XCFRAMEWORKS_VERSION}-ios-universal.tar.gz

.cache/xcframeworks/libmpv-xcframeworks-ios-universal.tar.gz: .cache/xcframeworks/libmpv-xcframeworks-${MPV_XCFRAMEWORKS_VERSION}-ios-universal.tar.gz
	rm -f .cache/xcframeworks/libmpv-xcframeworks-ios-universal.tar.gz
	ln -s libmpv-xcframeworks-${MPV_XCFRAMEWORKS_VERSION}-ios-universal.tar.gz .cache/xcframeworks/libmpv-xcframeworks-ios-universal.tar.gz

Frameworks/*.xcframework: .cache/xcframeworks/libmpv-xcframeworks-ios-universal.tar.gz
	mkdir -p Frameworks
	rm -rf Frameworks/*.xcframework
	tar -xvf .cache/xcframeworks/libmpv-xcframeworks-ios-universal.tar.gz --strip-components 1 -C Frameworks
	touch Frameworks/*.xcframework

Frameworks/.symlinks: Frameworks/*.xcframework
	rm -rf Frameworks/.symlinks
	mkdir -p Frameworks/.symlinks/mpv
	sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv

.PHONY: clean
clean:
	rm -rf .cache Frameworks
