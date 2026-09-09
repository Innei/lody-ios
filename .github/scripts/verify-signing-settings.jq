[.[] | .buildSettings |
  select($profiles[.PRODUCT_BUNDLE_IDENTIFIER] != null)] as $settings |
([$settings[].PRODUCT_BUNDLE_IDENTIFIER] | unique | sort) == ($profiles | keys | sort) and
all($settings[];
  .CODE_SIGN_STYLE == "Manual" and
  .CODE_SIGN_IDENTITY == "Apple Distribution" and
  .DEVELOPMENT_TEAM == $team and
  .PROVISIONING_PROFILE_SPECIFIER == $profiles[.PRODUCT_BUNDLE_IDENTIFIER])
