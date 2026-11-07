# bridge.ps1
#
# G2HUD PC bridge: lets the iPhone app ask Claude through this PC's Claude Code
# login. `claude -p` signed in with a Claude plan draws from the plan's usage
# limits, no API key (support.claude.com/en/articles/15036540, Oct 2026).
#
# Listens on 127.0.0.1 only. Tailscale Serve publishes it to your own devices
# over HTTPS (`tailscale serve --bg 8765`), so nothing is open to the internet.
# Claude runs in an empty folder (.\work) and may only use WebSearch/WebFetch.
#
# API (every request needs "Authorization: Bearer <token from token.txt>"):
#   GET  /health  -> {"ok": true}
#   POST /ask     body {"prompt": "...", "system": "...", "newSession": false}
#                 -> {"answer": "..."}  or  {"error": "..."}
#
# Run: double-click start-bridge.cmd (Windows PowerShell 5.1, nothing to install
# besides Claude Code itself).

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- constants
$Port = 8765                 # local port; must match `tailscale serve`
$ClaudeTimeoutSeconds = 120  # web searches can take a while
$MaxRequestBytes = 1MB
$AllowedTools = @('WebSearch', 'WebFetch')

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$TokenFile = Join-Path $Here 'token.txt'
$WorkDir = Join-Path $Here 'work'

$Utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $Utf8
$OutputEncoding = $Utf8

# ---------------------------------------------------------------- setup
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir | Out-Null }

if (-not (Test-Path $TokenFile)) {
    # 12 random bytes (~16 characters): short enough to type on the phone; the
    # bridge is only reachable from your own Tailscale devices anyway.
    $bytes = New-Object byte[] 12
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $newToken = ([Convert]::ToBase64String($bytes)) -replace '[+/=]', ''
    Set-Content -Path $TokenFile -Value $newToken -NoNewline -Encoding ASCII
}
$Token = (Get-Content -Path $TokenFile -Raw).Trim()

# Prefer the real executable; npm installs only have claude.cmd.
$ClaudeCommand = Get-Command claude.exe, claude.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $ClaudeCommand) {
    Write-Host 'Claude Code not found. Install it: irm https://claude.ai/install.ps1 | iex   then run: claude   (log in once)'
    Read-Host 'Press Enter to close'
    exit 1
}

$SessionId = $null   # Claude conversation kept between questions

# ---------------------------------------------------------------- claude
# Runs one `claude -p` turn. The prompt goes in through stdin (no quoting
# problems with Japanese or punctuation). Returns the answer text.
function Invoke-Claude([string]$Prompt, [string]$System, [bool]$NewSession) {
    if ($NewSession) { $script:SessionId = $null }

    # The system text goes on the command line: strip characters cmd/quoting would break.
    $safeSystem = ($System -replace '["%\r\n]', ' ').Trim()
    $arguments = @('-p', '--output-format', 'json', '--allowedTools') + $AllowedTools
    if ($script:SessionId) { $arguments += @('--resume', $script:SessionId) }
    if ($safeSystem) { $arguments += @('--append-system-prompt', "`"$safeSystem`"") }

    $info = New-Object System.Diagnostics.ProcessStartInfo
    if ($ClaudeCommand.Source -like '*.cmd') {
        $info.FileName = 'cmd.exe'
        $info.Arguments = '/c "' + $ClaudeCommand.Source + '" ' + ($arguments -join ' ')
    } else {
        $info.FileName = $ClaudeCommand.Source
        $info.Arguments = $arguments -join ' '
    }
    $info.WorkingDirectory = $WorkDir
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $Utf8
    $info.StandardErrorEncoding = $Utf8
    $info.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($info)
    $stdinWriter = New-Object System.IO.StreamWriter($process.StandardInput.BaseStream, $Utf8)
    $stdinWriter.Write($Prompt)
    $stdinWriter.Close()
    $outputTask = $process.StandardOutput.ReadToEndAsync()
    $errorTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($ClaudeTimeoutSeconds * 1000)) {
        $process.Kill()
        throw "Claude took longer than $ClaudeTimeoutSeconds s"
    }
    $output = $outputTask.Result
    if (-not $output.Trim()) { throw ('Claude error: ' + $errorTask.Result.Trim()) }

    $result = $output | ConvertFrom-Json
    if ($result.session_id) { $script:SessionId = $result.session_id }
    if ($result.is_error) { throw ('Claude error: ' + $result.result) }
    return [string]$result.result
}

# ---------------------------------------------------------------- http
# Minimal HTTP/1.1 over TcpListener (HttpListener rejects the Host header
# Tailscale Serve forwards, and needs admin rights for anything but localhost).

function Read-Request([System.Net.Sockets.NetworkStream]$Stream) {
    $buffer = New-Object byte[] 65536
    $data = New-Object System.IO.MemoryStream
    $headerEnd = -1
    while ($headerEnd -lt 0) {
        $count = $Stream.Read($buffer, 0, $buffer.Length)
        if ($count -le 0 -or $data.Length -gt $MaxRequestBytes) { return $null }
        $data.Write($buffer, 0, $count)
        $headerEnd = [Text.Encoding]::ASCII.GetString($data.ToArray()).IndexOf("`r`n`r`n")
    }

    $all = $data.ToArray()
    $headerLines = [Text.Encoding]::ASCII.GetString($all, 0, $headerEnd) -split "`r`n"
    $requestLine = $headerLines[0] -split ' '
    $headers = @{}
    foreach ($line in ($headerLines | Select-Object -Skip 1)) {
        $colon = $line.IndexOf(':')
        if ($colon -gt 0) { $headers[$line.Substring(0, $colon).Trim().ToLower()] = $line.Substring($colon + 1).Trim() }
    }

    $length = 0
    if ($headers['content-length']) { $length = [int]$headers['content-length'] }
    if ($length -gt $MaxRequestBytes) { return $null }
    $bodyStart = $headerEnd + 4
    while ($all.Length - $bodyStart -lt $length) {
        $count = $Stream.Read($buffer, 0, $buffer.Length)
        if ($count -le 0) { return $null }
        $data.Write($buffer, 0, $count)
        $all = $data.ToArray()
    }

    return @{
        Method  = $requestLine[0]
        Path    = $requestLine[1]
        Headers = $headers
        Body    = $Utf8.GetString($all, $bodyStart, $length)
    }
}

function Send-Json([System.Net.Sockets.NetworkStream]$Stream, [string]$Status, $Object) {
    $body = $Utf8.GetBytes(($Object | ConvertTo-Json -Compress))
    $head = "HTTP/1.1 $Status`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
    $headBytes = [Text.Encoding]::ASCII.GetBytes($head)
    $Stream.Write($headBytes, 0, $headBytes.Length)
    $Stream.Write($body, 0, $body.Length)
    $Stream.Flush()
}

function Handle-Request($Request, [System.Net.Sockets.NetworkStream]$Stream) {
    if ($Request.Headers['authorization'] -ne "Bearer $Token") {
        Send-Json $Stream '401 Unauthorized' @{ error = 'Wrong token' }
        return
    }
    if ($Request.Method -eq 'GET' -and $Request.Path -eq '/health') {
        Send-Json $Stream '200 OK' @{ ok = $true }
        return
    }
    if ($Request.Method -ne 'POST' -or $Request.Path -ne '/ask') {
        Send-Json $Stream '404 Not Found' @{ error = 'Not found' }
        return
    }

    $ask = $Request.Body | ConvertFrom-Json
    Write-Host ("[{0:HH:mm:ss}] ask: {1}" -f (Get-Date), $ask.prompt)
    try {
        $answer = Invoke-Claude ([string]$ask.prompt) ([string]$ask.system) ([bool]$ask.newSession)
        Write-Host ("[{0:HH:mm:ss}] answer: {1}" -f (Get-Date), $answer)
        Send-Json $Stream '200 OK' @{ answer = $answer }
    } catch {
        Write-Host ("[{0:HH:mm:ss}] error: {1}" -f (Get-Date), $_.Exception.Message)
        Send-Json $Stream '500 Internal Server Error' @{ error = $_.Exception.Message }
    }
}

# ---------------------------------------------------------------- main loop
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
Write-Host "G2HUD bridge running on 127.0.0.1:$Port  (Claude Code: $($ClaudeCommand.Source))"
Write-Host "Token for the app: $Token"
Write-Host 'Keep this window open. Ctrl+C to stop.'

while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
        $client.ReceiveTimeout = 10000
        $stream = $client.GetStream()
        $request = Read-Request $stream
        if ($request) { Handle-Request $request $stream }
    } catch {
        Write-Host ("[{0:HH:mm:ss}] connection error: {1}" -f (Get-Date), $_.Exception.Message)
    } finally {
        $client.Close()
    }
}
