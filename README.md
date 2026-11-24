# Project Amethyst

A native, offline iPhone security inspector and compatibility reference. Version 0.1 Pre-Alpha targets arm64 iPhones running iOS 15 or later. The initial research target is iPhone 11 Pro Max (iPhone12,5, A13) on iOS 27.0.1. That combination has no on-device validation in this release.

## Install

1. Open [Amethyst iOS Build](https://github.com/angie689/project-amethyst/actions/workflows/ios.yml) and select a successful main build. Download the **Amethyst-unsigned** artifact and unzip it once to obtain Amethyst.ipa. GitHub may require sign-in for artifact downloads.
2. Follow the [SideStore setup guide](https://docs.sidestore.io/) for your firmware. Import the IPA using the plus button in My Apps. SideStore signs the app with your Apple ID. A free account is sufficient subject to Apple’s provisioning limits and refresh period.
3. For [LiveContainer](https://github.com/LiveContainer/LiveContainer), import the IPA into an already configured host using its documented JIT-less mode. Host support depends on the OS and signing setup. Measurements then describe the hosted process. Neither installation route has been verified on the target firmware.

The app requires no login, JIT, network service, elevated entitlements or jailbreak. Reference links open externally.

## Use

Overview shows the current system build, kernel, volume capacity, process architecture and memory readings. Chip names come from a small hardware identifier table. Available memory is the app’s remaining allocation budget. Resident memory is the size of its resident pages.

Advisories and Compatibility search separate local catalogs. Open a record for its scope and upstream references. A CVE match describes published exposure. It cannot establish exploitability or jailbreak support. Compatibility is assessed per named project release. Unknown covers missing hardware mappings, unrecognized builds and firmware outside the catalog’s evidence. A conventional release build number alone cannot distinguish every release candidate from a final release.

Run Diagnostics to sample the current process and try read-only directory listings. A listing failure includes the API error code. It cannot identify the enforcing policy by itself. Console exports a UTF-8 text file through Files. The gear on Overview controls whether the snapshot is appended to the report; diagnostic messages can also contain device details. Logs are bounded and session-only.

## Develop

Open Amethyst.xcodeproj in Xcode 16 or later. Choose an iPhone simulator and Run, or execute the following from the repository root on a Mac with Xcode command-line tools selected:

```sh
swiftc Amethyst/Catalog.swift Tests/main.swift -o /tmp/amethyst-tests
/tmp/amethyst-tests
Scripts/build.sh
```

The script builds Release for iphoneos with signing disabled and verifies build/Amethyst.ipa before publishing it. The checked-in Xcode project has no package dependencies. GitHub Actions runs the same tests and packaging on pushes to main and manual dispatch.

Edit Amethyst/catalog.json to add records. Include upstream references, a hardware and firmware scope, and inclusive numeric bounds. Rules match exact hardware identifiers in file order. Omitted bounds are open. Project verdicts are Supported, Experimental, Unsupported and Unknown. Reserve Experimental for an upstream experimental designation. Update Tests/main.swift for new boundaries and unknown cases.

## Roadmap

- Validate installation, report export and runtime readings on the initial physical device and in LiveContainer.
- Expand reviewed hardware mappings and versioned project records with regression tests.
- Add build-specific advisory exceptions and review dates as coverage grows.

Distributed under the [MIT License](LICENSE).
