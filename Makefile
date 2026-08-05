IOS_DIR := apps/ios/OctoTeacher
IOS_PROJECT := $(IOS_DIR)/OctoTeacher.xcodeproj
IOS_SCHEME := OctoTeacher
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17

.PHONY: doctor ios-generate ios-parse ios-lint ios-build ios-test ios-open portal-install portal-dev portal-check api-install api-check

doctor:
	@sw_vers
	@xcode-select -p
	@xcodebuild -version
	@command -v xcodegen
	@command -v swiftlint
	@command -v git

ios-generate:
	cd $(IOS_DIR) && xcodegen generate

ios-parse:
	swiftc -parse $$(rg --files $(IOS_DIR)/OctoTeacherApp -g '*.swift')

ios-lint:
	swiftlint lint --config $(IOS_DIR)/.swiftlint.yml

ios-build: ios-generate
	set -o pipefail; xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) -destination '$(IOS_DESTINATION)' build | xcbeautify

ios-test: ios-generate
	set -o pipefail; xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) -destination '$(IOS_DESTINATION)' test | xcbeautify

ios-open: ios-generate
	open $(IOS_PROJECT)

portal-install:
	npm install --prefix apps/portal

portal-dev:
	npm run dev --prefix apps/portal

portal-check:
	npm run lint --prefix apps/portal
	npm run build --prefix apps/portal

api-install:
	npm install --prefix services/api

api-check:
	npm run typecheck --prefix services/api
	npm test --prefix services/api
	npm run build --prefix services/api
