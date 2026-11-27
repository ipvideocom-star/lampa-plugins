#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root)
$ErrorActionPreference = 'Stop'
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add('http://127.0.0.1:9191/')
$listener.Start()
try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    try {
      $file = switch ($ctx.Request.Url.AbsolutePath) {
        '/primary.m3u' { Join-Path $Root 'Provider-Primary-PRIVATE.m3u'; break }
        '/reserve.m3u' { Join-Path $Root 'Provider-Reserve-PRIVATE.m3u'; break }
        default { $null }
      }
      if ($ctx.Request.HttpMethod -notin @('GET','HEAD')) {
        $ctx.Response.StatusCode = 405
      } elseif (!$file -or !(Test-Path -LiteralPath $file -PathType Leaf)) {
        $ctx.Response.StatusCode = 404
      } else {
        $content = [IO.File]::ReadAllBytes($file)
        $ctx.Response.ContentType = 'application/x-mpegURL'
        $ctx.Response.ContentLength64 = $content.Length
        $ctx.Response.Headers.Add('Cache-Control','no-store')
        if ($ctx.Request.HttpMethod -eq 'GET') {
          $ctx.Response.OutputStream.Write($content,0,$content.Length)
        }
      }
    } catch {
      try { $ctx.Response.StatusCode = 500 } catch {}
    } finally {
      try { $ctx.Response.Close() } catch {}
    }
  }
} finally {
  $listener.Stop()
  $listener.Close()
}
