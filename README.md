# Project Amethyst

A native, offline iPhone security inspector and compatibility reference. Version 0.2 Pre-Alpha targets arm64 iPhones running iOS 15 or later. The initial research target is iPhone 11 Pro Max (iPhone12,5, A13) on iOS 27.0.1. That combination has no on-device validation in this release.

## Install

1. Open [Amethyst iOS Build](https://github.com/angie689/project-amethyst/actions/workflows/ios.yml) and select a successful main build. Download the **Amethyst-unsigned** artifact and unzip it once to obtain Amethyst.ipa. GitHub may require sign-in for artifact downloads.
2. Follow the [SideStore setup guide](https://docs.sidestore.io/) for your firmware. Import the IPA using the plus button in My Apps. SideStore signs the app with your Apple ID. A free account is sufficient subject to Apple’s provisioning limits and refresh period.
3. For [LiveContainer](https://github.com/LiveContainer/LiveContainer), import the IPA into an already configured host using its documented JIT-less mode. Host support depends on the OS and signing setup. Measurements then describe the hosted process. Neither installation route has been verified on the target firmware.

To update v0.1, use the same signer and bundle identifier and install the new IPA over the existing app. Check Settings for version 0.2. The GitHub build summary reports the size of the IPA inside the artifact.

The app requires no login, JIT, network service, elevated entitlements or jailbreak. Reference links open externally.

## Use

Overview shows the current system build, kernel, volume capacity, process architecture and memory readings. Chip names come from a small hardware identifier table. Available memory is the app’s remaining allocation budget. Resident memory is the size of its resident pages.

Advisories and Compatibility search separate local catalogs. Open a record for its scope and upstream references. A CVE match describes published exposure. It cannot establish exploitability or jailbreak support. Compatibility is assessed per named project release. Unknown covers missing hardware mappings, unrecognized builds and firmware outside the catalog’s evidence. A conventional release build number alone cannot distinguish every release candidate from a final release.

**Diagnostics** runs individual or grouped probes for sysctl hardware and kernel keys, Mach task VM and thread counts, interface names, loaded image names, statfs capacity, descriptor limits, Metal and read-only directory access. Open a row for its timestamp, returned value, and error domain/code when the API supplies one. Accessible means the call succeeded. Restricted represents POSIX EPERM, Denied represents EACCES or Mach protection failure, and Unavailable covers other errors or a missing device. Untested includes probes outside the public SDK, such as general IOKit registry inspection. A permission error is an observation about this process.

**Analyze a file** uses the Files picker. Open an IPS, crash, panic, jetsam or analytics file to search extracted fields and preview lines. JSON parsing handles an Apple metadata header followed by a separate report body. Text previews read up to 4 MiB. For sysdiagnose tar/gzip archives, search a preview of member names and sizes (up to 200 entries or 16 MiB decompressed). ZIP inventories inspect up to 4096 directory entries. IPSW inspection reads stored or deflated root Restore.plist and BuildManifest.plist members up to 4 MiB each. Plists can also be imported directly. Archives stay on disk, and analysis runs locally. Encrypted archives, full sysdiagnose decoding, and crash symbolication are outside this release.

**Console** can run a single probe, filter by message or severity, export plain text or structured JSON, and compare the latest assessment with a previous one. Five completed assessments persist in app preferences. Each records its device, OS build, advisory verdicts, and probe results. Console messages stay in memory. Settings controls the additional overview section of an export. Assessment and console records can contain device details regardless of this setting.

**Overview** plots resident memory and CPU time every two seconds while the view is active. CPU usage is relative to one core and can exceed 100%. Each trace scales to its recent samples. The brief launch animation runs when SwiftUI appears following the static iOS launch screen. Reduce Motion suppresses it.

**Advisory coverage** for the two bundled CVEs requires a mapped iPhone, ARM64, and an exact reviewed release pair (16.6/20G75 or 16.6.1/20G81). Other pairs, including iOS 27, return Unknown. Amethyst does not test exploitability.

## Develop

Open Amethyst.xcodeproj in Xcode 16 or later. Choose an iPhone simulator and Run, or execute the following from the repository root on a Mac with Xcode command-line tools selected:

```sh
Scripts/test.sh
Scripts/build.sh
```

The script builds Release for iphoneos with signing disabled and verifies build/Amethyst.ipa before publishing it. The checked-in Xcode project has no package dependencies. GitHub Actions runs the same tests and packaging on pushes to main and manual dispatch.

Edit Amethyst/catalog.json to add records. Include upstream references, a hardware and firmware scope, and inclusive numeric bounds. Rules match exact hardware identifiers in file order. Omitted bounds are open. Project verdicts are Supported, Experimental, Unsupported and Unknown. Reserve Experimental for an upstream experimental designation. Update Tests/main.swift for new boundaries and unknown cases.

## Roadmap

- Validate installation, report export and runtime readings on the initial physical device and in LiveContainer.
- Expand reviewed hardware mappings and versioned project records with regression tests.
- Expand verified OS/build pairs and record source review dates.

Distributed under the [MIT License](LICENSE).
