# Fast N Fresh v1.1.0+4 Build Fixes

Fixed compile errors reported by `flutter build apk --release`:

- `ExpensesScreen`: `_categories` is now explicitly typed and `const`.
- `ProductImagePicker`: compression configuration is now declared as static const fields (`_sizes`, `_qualities`, `_maxBytes`) instead of undefined instance members.
- `FastNFreshApp` and the main navigation screen constructors are now const-compatible.
- MainShell page lists remain typed as `List<Widget>` through const widget constructors.
- Added const constructors to the affected immutable screen/widgets to resolve const-expression errors.

The previous 1084 analyzer diagnostics were mostly lint/info suggestions; these changes target the actual compiler errors shown in the release build log.
