$css = @"

/* ---- Ad rail: collapse entirely when no ad content has loaded ---- */
.ad-rail:empty,
.ad-left:empty,
.ad-right:empty,
.ad-bottom:empty {
  display: none !important;
}
.ad-rail, .ad-left, .ad-right, .ad-bottom {
  pointer-events: none;
}
"@
Add-Content -Path 'styles.css' -Value $css -Encoding UTF8
Write-Host "Done."
