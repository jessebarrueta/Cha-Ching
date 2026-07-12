# enormousbrain.com Universal Link Files

These files are for the app invite flow:

```text
https://enormousbrain.com/cha-ching/invite/<token>
```

## Files To Publish

Publish the fallback page here:

```text
Website/enormousbrain/cha-ching/invite/index.html
```

to:

```text
https://enormousbrain.com/cha-ching/invite/
```

Publish the Apache rewrite/content-type rules here:

```text
Website/enormousbrain/.htaccess
```

to:

```text
https://enormousbrain.com/.htaccess
```

This keeps `/cha-ching/invite/<token>` on the fallback page when the app is not installed, and serves the Apple association file as JSON.

Publish the Apple association file here:

```text
Website/enormousbrain/.well-known/apple-app-site-association
```

to:

```text
https://enormousbrain.com/.well-known/apple-app-site-association
```

The final file must be served over HTTPS without a redirect. It should not have a `.json` extension.

## Current App Values

```text
Apple Team ID: RER3T958QE
Bundle ID: com.jessebarrueta.ChaChing
Associated domain: applinks:enormousbrain.com
Invite base URL: https://enormousbrain.com/cha-ching/invite
```
