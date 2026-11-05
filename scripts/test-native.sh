#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $(uname -s) != Darwin ]]; then echo "Native fixtures require macOS and Xcode." >&2; exit 1; fi
mkdir -p .build
case "${1:-all}" in
  jailbreak|jailed|all) ;;
  *) echo "Usage: bash scripts/test-native.sh [jailbreak|jailed|all]" >&2; exit 1;;
esac

if [[ ${1:-all} == jailbreak || ${1:-all} == all ]]; then
  # Mach reply-port transport
  mkdir -p .build
  clang -fobjc-arc -framework Foundation tests/mach_transport.m -o .build/mach-transport-test
  .build/mach-transport-test
  clang -fobjc-arc -framework Foundation tests/ipc_client.m -o .build/ipc-client-test
  .build/ipc-client-test
  clang -fobjc-arc -framework Foundation tests/sandbox_access.m -o .build/sandbox-access-test
  .build/sandbox-access-test
  clang -fobjc-arc -framework Foundation '-DTHEOS_PACKAGE_INSTALL_PREFIX="/var/jb"' tests/sandbox_access.m -o .build/sandbox-access-rootless-test
  .build/sandbox-access-rootless-test
  clang -fblocks tests/discovery.c -o .build/discovery-test
  .build/discovery-test
  clang -fblocks Shared/GSDiscovery.c Daemon/GSDiscoveryService.c tests/discovery_launchd.c -o .build/discovery-launchd-test
  python3 scripts/test-discovery-launchd.py .build/discovery-launchd-test
  clang -fobjc-arc -framework Foundation -framework CoreFoundation tests/daemon_runloop.m -o .build/daemon-runloop-test
  .build/daemon-runloop-test
  # Jailbreak native account relay
  clang -fobjc-arc -DGS_TEST_DAEMON_RELAY=1 -DGS_TEST_AUTOCONNECT=1 -framework Foundation Native/GSNativeAccount.m Native/GSNativeRelay.m Native/GSAccountConnection.m tests/native_account.m -o .build/native-relay-test
  .build/native-relay-test
  clang -fobjc-arc -DGS_TEST_DAEMON_RELAY=1 -DGS_TEST_AUTOCONNECT=1 -DGS_TEST_LEGACY=1 -framework Foundation Native/GSNativeAccount.m Native/GSNativeRelay.m Native/GSAccountConnection.m tests/native_account.m -o .build/native-relay-legacy-test
  .build/native-relay-legacy-test
  clang -fobjc-arc -DGS_JAILED=1 -DGS_TEST_AUTOCONNECT=1 -framework Foundation Native/GSNativeAccount.m Native/GSAccountConnection.m tests/native_account.m -o .build/native-autoconnect-jailed-test
  .build/native-autoconnect-jailed-test
  clang -fobjc-arc -DGS_JAILED=1 -DGS_TEST_AUTOCONNECT=1 -DGS_TEST_LEGACY=1 -framework Foundation Native/GSNativeAccount.m Native/GSAccountConnection.m tests/native_account.m -o .build/native-autoconnect-jailed-legacy-test
  .build/native-autoconnect-jailed-legacy-test
  # Jailbreak backup routing and shared completion monitor
  clang -fobjc-arc -framework Foundation -Itests/native-shims Native/GSNativeAccount.m Native/GSNativeRouting.m Native/GSBackupRequests.m tests/backup_requests.m -o .build/daemon-backup-test
  .build/daemon-backup-test
  clang -fobjc-arc -DGS_TEST_LEGACY=1 -framework Foundation -Itests/native-shims Native/GSNativeAccount.m Native/GSNativeRouting.m Native/GSBackupRequests.m tests/backup_requests.m -o .build/daemon-backup-legacy-test
  .build/daemon-backup-legacy-test
  clang -fobjc-arc -framework Foundation -Itests/native-shims Native/GSNativeAccount.m Native/GSUploadMonitor.m Native/GSPhotosIntegration.m tests/upload_monitor.m -o .build/upload-monitor-test
  .build/upload-monitor-test
fi

if [[ ${1:-all} == jailed || ${1:-all} == all ]]; then
  # Sideload SSO compatibility
  mkdir -p .build
  clang -fobjc-arc -framework Foundation -framework Security -framework LocalAuthentication tests/sideload_keychain.m -o .build/sideload-keychain-test
  .build/sideload-keychain-test
  for mode in native-private wrong-host livecontainer missing-configuration missing-helper configuration-abi helper-abi; do
    .build/sideload-keychain-test "$mode"
  done
  clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -framework Foundation tests/sideload_identity.m -o .build/sideload-identity-test
  for mode in modern legacy future wrong-host livecontainer original-id missing-id empty-id missing-configuration configuration-abi client-abi service-abi; do
    .build/sideload-identity-test "$mode"
  done
  # Native routing contract
  mkdir -p .build
  clang -fobjc-arc -framework Foundation tests/localization.m -o .build/localization-test
  .build/localization-test
  clang -fobjc-arc -c Native/GSUnlimitedStorage.m -o .build/unlimited-storage.o
  clang -fobjc-arc -c tests/unlimited_storage.m -o .build/unlimited-storage-fixture.o
  swiftc -parse-as-library -emit-object -import-objc-header tests/unlimited_storage_fixture.h tests/unlimited_storage.swift -o .build/unlimited-storage-swift.o
  swiftc .build/unlimited-storage.o .build/unlimited-storage-fixture.o .build/unlimited-storage-swift.o -o .build/unlimited-storage-test
  .build/unlimited-storage-test
  .build/unlimited-storage-test incompatible-abi
  .build/unlimited-storage-test bento-only
  clang -fobjc-arc -framework Foundation -Itests/native-shims Native/GSNativeRouting.m tests/native_routing.m -o .build/native-routing-test
  .build/native-routing-test
  clang -fobjc-arc -DGS_JAILED=1 -framework Foundation -Itests/native-shims Native/GSNativeRouting.m tests/native_routing.m -o .build/silent-jailed-routing-test
  .build/silent-jailed-routing-test
  clang -fobjc-arc -DGS_JAILED=1 -framework Foundation -Itests/native-shims Native/GSNativeAccount.m Native/GSNativeRouting.m Native/GSBackupRequests.m tests/backup_requests.m -o .build/backup-requests-test
  .build/backup-requests-test
  clang -fobjc-arc -framework Foundation -Itests/native-shims Native/GSPhotosIntegration.m tests/photos_integration.m -o .build/photos-integration-test
  .build/photos-integration-test
  clang -fobjc-arc -DGS_TEST_POLICY_ON_BASE=1 -framework Foundation -Itests/native-shims Native/GSPhotosIntegration.m tests/photos_integration.m -o .build/photos-integration-policy-test
  .build/photos-integration-policy-test
  clang -fobjc-arc -framework Foundation Native/GSUploadDiagnostics.m tests/upload_diagnostics.m -o .build/upload-diagnostics-test
  .build/upload-diagnostics-test
  clang -fobjc-arc -framework Foundation Native/GSNativeAccount.m tests/native_account.m -o .build/native-account-test
  .build/native-account-test
  clang -fobjc-arc -framework Foundation -Itests/menu-shims -Itests/native-shims UI/GSAccountMenu.m tests/account_menu.m -o .build/account-menu-test
  .build/account-menu-test
  # Google Photos 7.20.2 native contracts
  clang -fobjc-arc -framework Foundation Native/GSUnlimitedStorage.m tests/unlimited_storage_legacy.m -o .build/unlimited-storage-legacy-test
  .build/unlimited-storage-legacy-test
  .build/unlimited-storage-legacy-test missing-resources
  clang -fobjc-arc -DGS_TEST_LEGACY=1 -framework Foundation -Itests/native-shims Native/GSNativeRouting.m tests/native_routing.m -o .build/native-routing-legacy-test
  .build/native-routing-legacy-test
  clang -fobjc-arc -DGS_TEST_LEGACY=1 -DGS_JAILED=1 -framework Foundation -Itests/native-shims Native/GSNativeRouting.m tests/native_routing.m -o .build/silent-jailed-routing-legacy-test
  .build/silent-jailed-routing-legacy-test
  clang -fobjc-arc -DGS_TEST_LEGACY=1 -DGS_JAILED=1 -framework Foundation -Itests/native-shims Native/GSNativeAccount.m Native/GSNativeRouting.m Native/GSBackupRequests.m tests/backup_requests.m -o .build/backup-requests-legacy-test
  .build/backup-requests-legacy-test
  clang -fobjc-arc -DGS_TEST_LEGACY=1 -framework Foundation -Itests/native-shims Native/GSPhotosIntegration.m tests/photos_integration.m -o .build/photos-integration-legacy-test
  .build/photos-integration-legacy-test
  clang -fobjc-arc -DGS_TEST_LEGACY=1 -framework Foundation Native/GSUploadDiagnostics.m tests/upload_diagnostics.m -o .build/upload-diagnostics-legacy-test
  .build/upload-diagnostics-legacy-test
  clang -fobjc-arc -DGS_TEST_LEGACY=1 -framework Foundation Native/GSNativeAccount.m tests/native_account.m -o .build/native-account-legacy-test
  .build/native-account-legacy-test
  clang -fobjc-arc -DGS_TEST_LEGACY=1 -framework Foundation -Itests/menu-shims -Itests/native-shims UI/GSAccountMenu.m tests/account_menu.m -o .build/account-menu-legacy-test
  .build/account-menu-legacy-test
  # API detection independent of host version
  clang -fobjc-arc -framework Foundation tests/photos_compatibility.m -o .build/photos-compatibility-test
  .build/photos-compatibility-test
  for version in 7.20.1 7.50.0 7.93.0 8.0.0 unknown; do
    export GS_TEST_PHOTOS_VERSION="$version"
    .build/unlimited-storage-test
    .build/unlimited-storage-test incompatible-abi
    .build/unlimited-storage-test bento-only
    .build/native-routing-test
    .build/silent-jailed-routing-test
    .build/backup-requests-test
    .build/photos-integration-test
    .build/upload-diagnostics-test
    .build/native-account-test
    .build/account-menu-test
    .build/backup-requests-legacy-test
    .build/photos-integration-legacy-test
    .build/native-account-legacy-test
  done
  # Bulk photo import
  clang -fobjc-arc -framework Foundation -Itests/native-shims Media/GSBatchImport.m tests/batch_import.m -o .build/batch-import-test
  .build/batch-import-test
  clang -fobjc-arc -framework Foundation -framework UniformTypeIdentifiers -Itests/native-shims Media/GSBatchImport.m Media/GSExporter.m tests/exporter_batch.m -o .build/exporter-batch-test
  .build/exporter-batch-test
fi
