# TestFlight Deployment Handoff

These notes are for getting the current ChaChing iOS app onto a few phones with TestFlight.

## Important ownership note

GitHub collaborator access only gives access to the source code. TestFlight upload has to happen from a paid Apple Developer Program team.

If the collaborator uses their own paid Apple Developer account, the App Store Connect app and TestFlight build will live under their Apple team for now. That is fine for early testing, but it means the bundle ID, App Store Connect record, and universal-link association may need to change again later if the app moves to Jesse's own Apple Developer account.

The cleaner long-term path is: Jesse enrolls in Apple Developer Program, creates/owns the app in App Store Connect, and adds the collaborator as a user with enough permissions to upload builds. The faster path is: collaborator owns the temporary TestFlight app under their paid team.

## Current project facts

- Repo: `https://github.com/jessebarrueta/Cha-Ching`
- Project: `ChaChing.xcodeproj`
- Scheme: `ChaChing`
- iOS deployment target: `17.0`
- Display name: controlled in `Configuration/AppBrand.xcconfig` as `APP_DISPLAY_NAME = Do Good`
- Marketing version: `1.0`
- Current build number: `2`
- Current bundle ID: `com.jessebarrueta.ChaChing`
- Current development team in the project file: `RER3T958QE` (an Apple Team ID, not an Apple account email)
- Associated domain entitlement: `applinks:enormousbrain.com`

No OpenAI API key is needed on the Mac that uploads the app. AI review runs through the Supabase Edge Function, and those secrets are already configured server-side.

## One-time local setup

1. Install the latest stable Xcode from the Mac App Store.
2. Clone the repo:

   ```sh
   git clone https://github.com/jessebarrueta/Cha-Ching.git
   cd Cha-Ching
   git checkout codex/initial-mvp
   ```

3. Open `ChaChing.xcodeproj` in Xcode.
4. In Xcode, go to `Xcode > Settings > Accounts` and add the Apple ID that belongs to the paid Developer Program team.
5. Select the `ChaChing` project, then the `ChaChing` app target.
6. In `Signing & Capabilities`, select the paid team.
7. Leave `Automatically manage signing` enabled unless you have a reason to manage profiles manually.

## Bundle ID decision

The bundle ID used in Xcode must match the App ID / bundle ID used in App Store Connect.

If the collaborator is uploading under their own paid Apple team, they may need to change the bundle ID to one controlled by that team, for example:

```text
com.<their-org-or-name>.ChaChing
```

If the bundle ID changes:

- Change `PRODUCT_BUNDLE_IDENTIFIER` in the `ChaChing` target build settings.
- Use that exact bundle ID when creating the App Store Connect app record.
- Ask Jesse to update the `apple-app-site-association` file on `enormousbrain.com`, because universal links use the Apple Team ID plus bundle ID.
- Coordinate before committing that change, because it changes the app identity for every future build.

The project already has the Associated Domains entitlement for `applinks:enormousbrain.com`, so the paid team provisioning profile must support that capability.

## Create the App Store Connect app record

In App Store Connect:

1. Go to `Apps`.
2. Click `+`.
3. Choose `New App`.
4. Use:
   - Platform: `iOS`
   - Name: `Do Good` or `Cha-Ching`, whichever Jesse wants for this test
   - Primary language: `English`
   - Bundle ID: the exact bundle ID selected in Xcode
   - SKU: something stable like `cha-ching-ios`
5. Create the app record.

## Archive and upload from Xcode

1. In Xcode, select `Any iOS Device (arm64)` or a connected physical iPhone as the run destination.
2. Bump the build number if re-uploading the same version. The current project build number is `2`; the next upload should be `3`.
3. Choose `Product > Archive`.
4. When Organizer opens, select the archive.
5. Click `Distribute App`.
6. Choose `App Store Connect`.
7. Choose `Upload`.
8. Use automatic signing/provisioning unless manual signing is required for the team.
9. Finish the upload and wait for App Store Connect processing. Apple sends an email when processing completes.

Transporter is also valid if you prefer exporting an IPA and uploading separately, but Xcode upload is the simplest path.

## TestFlight setup

Once the build appears in App Store Connect:

1. Open the app in App Store Connect.
2. Go to the `TestFlight` tab.
3. Fill in the beta test information:
   - Beta app description
   - What to test
   - Feedback email
4. If the build is marked `Missing Compliance`, answer the export compliance questions. The app uses normal HTTPS networking and does not include custom cryptography, but the person uploading should answer Apple's questions accurately.
5. Create an internal testing group first.
6. Add App Store Connect users as internal testers if applicable.
7. For Jesse, family, or friends who are not App Store Connect users, create an external testing group.
8. Add the build to that external group and invite testers by email or public TestFlight link.

Apple allows up to 100 internal App Store Connect testers and up to 10,000 external testers. The first external TestFlight build may require beta App Review before external testers can install it.

If Jesse is not an App Store Connect user on the collaborator's Apple team, invite him as an external tester.

## Smoke test checklist

On a real phone from TestFlight:

- App launches.
- Family/role setup appears.
- Child and parent views show the same seeded family content.
- Camera permission prompt appears when taking evidence.
- A photo can be captured and submitted.
- AI review returns a confidence result instead of staying stuck.
- Parent review queue shows the submitted item.
- Universal invite links to `enormousbrain.com` open correctly. If not, re-check the Associated Domains entitlement and the website's `apple-app-site-association` file.

## Useful Apple docs

- [Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id/)
- [Add a new app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)
- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)
- [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)
- [Provide export compliance information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds)
