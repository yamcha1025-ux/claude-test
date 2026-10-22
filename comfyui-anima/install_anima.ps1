# ComfyUI + Anima (img2img denoise) 설치 스크립트 - D 드라이브 기준
# - 기존 파일/모델/설정은 삭제하거나 덮어쓰지 않습니다 (있으면 건너뜀).
# - 공식 출처만 사용: github.com/comfyanonymous/ComfyUI 릴리스, huggingface.co/circlestone-labs/Anima
# - 시스템 실행 정책 등 보안 설정은 바꾸지 않습니다.
param(
    [string]$Drive = "D:",
    [string]$ComfyRoot = "",          # 기존 ComfyUI 폴더(main.py가 있는 폴더)를 직접 지정할 때
    [switch]$CheckOnly                # 점검만 하고 아무것도 받지 않음
)
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkDir = Join-Path $Drive "AnimaTest"
$PortableDir = Join-Path $Drive "ComfyUI_windows_portable"
$DownloadDir = Join-Path $Drive "ComfyUI_downloads"
$HF = "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files"
$Models = @(
    @{ Sub = "diffusion_models"; Name = "anima-base-v1.0.safetensors"; Sha256 = "bd43b7cffe1ed1153d9c41e7beb2f18cb1273eafbaa3af3edd6a173dc90a006e" },
    @{ Sub = "text_encoders";    Name = "qwen_3_06b_base.safetensors"; Sha256 = "" },
    @{ Sub = "vae";              Name = "qwen_image_vae.safetensors";  Sha256 = "" }
)

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }

# ---------- 1. 환경 점검 ----------
Say "`n[1] GPU / VRAM / 디스크 점검" Cyan
$gpus = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion
$gpus | ForEach-Object { Say ("  GPU: {0} (driver {1})" -f $_.Name, $_.DriverVersion) }
$nvidia = $null
$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($smi) {
    $q = & nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits
    $nvidia = ($q | Select-Object -First 1).Split(",") | ForEach-Object { $_.Trim() }
    Say ("  NVIDIA: {0}, VRAM {1} MiB, driver {2}" -f $nvidia[0], $nvidia[1], $nvidia[2]) Green
    if ([int]$nvidia[1] -lt 6000) { Say "  경고: VRAM 6GB 미만 - 느리거나 메모리 부족이 날 수 있습니다." Yellow }
} else {
    Say "  nvidia-smi 없음 (NVIDIA GPU가 아니거나 드라이버 미설치)." Yellow
}
$disk = Get-PSDrive ($Drive.TrimEnd(":")) -ErrorAction SilentlyContinue
if (-not $disk) { throw "$Drive 드라이브를 찾을 수 없습니다." }
$freeGB = [math]::Round($disk.Free / 1GB, 1)
Say "  $Drive 여유 공간: $freeGB GB (신규 설치 시 약 20GB 권장: 포터블 ~2GB 압축+~7GB 해제, 모델 ~5.6GB)"

# ---------- 2. 기존 ComfyUI 찾기 ----------
Say "`n[2] 기존 ComfyUI 찾기" Cyan
$found = @()
if ($ComfyRoot) { $found += (Resolve-Path $ComfyRoot).Path }
$cands = @("D:\ComfyUI_windows_portable\ComfyUI", "C:\ComfyUI_windows_portable\ComfyUI", "D:\ComfyUI", "C:\ComfyUI",
           "$env:USERPROFILE\Desktop\ComfyUI_windows_portable\ComfyUI", "$env:USERPROFILE\Downloads\ComfyUI_windows_portable\ComfyUI",
           "$env:USERPROFILE\Documents\ComfyUI")
foreach ($d in @("C:\", "D:\")) {
    if (Test-Path $d) {
        Get-ChildItem $d -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $cands += $_.FullName; $cands += (Join-Path $_.FullName "ComfyUI")
        }
    }
}
foreach ($c in $cands | Select-Object -Unique) {
    if ((Test-Path (Join-Path $c "main.py")) -and (Test-Path (Join-Path $c "comfy"))) { $found += (Resolve-Path $c).Path }
}
# ComfyUI Desktop 앱(모델/설정이 Documents\ComfyUI 에 있음)
if (Test-Path "$env:LOCALAPPDATA\Programs\ComfyUI\ComfyUI.exe") { Say "  ComfyUI Desktop 앱 설치 감지: $env:LOCALAPPDATA\Programs\ComfyUI" Yellow }
$found = $found | Select-Object -Unique
$found | ForEach-Object { Say "  발견: $_" Green }

if ($CheckOnly) { Say "`n점검만 완료(-CheckOnly). 아무것도 받지 않았습니다." Cyan; exit 0 }

if ($found.Count -ge 1) {
    if ($found.Count -gt 1 -and -not $ComfyRoot) {
        for ($i = 0; $i -lt $found.Count; $i++) { Say "  [$i] $($found[$i])" }
        $sel = Read-Host "사용할 ComfyUI 번호를 입력하세요"
        $Comfy = $found[[int]$sel]
    } else { $Comfy = $found[0] }
    Say "  기존 설치를 그대로 사용합니다(덮어쓰지 않음): $Comfy" Green
    $verFile = Join-Path $Comfy "comfyui_version.py"
    if (Test-Path $verFile) { Say ("  " + (Select-String -Path $verFile -Pattern "__version__").Line) }
    if (-not (Test-Path (Join-Path $Comfy "comfy\ldm\anima"))) {
        Say "  이 ComfyUI에는 Anima 지원 코드가 없습니다 (너무 오래된 버전). 업데이트가 필요합니다." Red
        Say "  기존 설치를 보호하기 위해 자동 업데이트는 하지 않습니다. 포터블이면 update\update_comfyui.bat 을 직접 실행한 뒤 다시 실행하세요." Red
        exit 1
    }
} else {
    # ---------- 3. 공식 포터블 신규 설치 ----------
    Say "`n[3] 기존 설치 없음 -> 공식 Windows 포터블을 $PortableDir 에 설치" Cyan
    if ($freeGB -lt 20) { throw "$Drive 여유 공간이 20GB 미만($freeGB GB)입니다. 공간 확보 후 다시 실행하세요." }
    if (Test-Path $PortableDir) { throw "$PortableDir 폴더가 이미 있습니다(ComfyUI 아님). 덮어쓰지 않도록 중단합니다." }
    if ($nvidia) {
        # 최신 nvidia 빌드는 최신 CUDA 런타임을 쓰므로 오래된 드라이버는 cu126 빌드 사용
        $asset = if ([double]($nvidia[2].Split(".")[0]) -lt 580) { "ComfyUI_windows_portable_nvidia_cu126.7z" } else { "ComfyUI_windows_portable_nvidia.7z" }
    } elseif ($gpus.Name -match "AMD|Radeon") {
        $asset = "ComfyUI_windows_portable_amd.7z"
    } else {
        throw "지원 GPU(NVIDIA/AMD)를 찾지 못했습니다. CPU 전용 실행은 매우 느려 설치를 중단합니다."
    }
    New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
    $archive = Join-Path $DownloadDir $asset
    if (-not (Test-Path $archive)) {
        $url = "https://github.com/comfyanonymous/ComfyUI/releases/latest/download/$asset"
        Say "  다운로드: $url"
        & curl.exe -L --fail --retry 3 -C - -o "$archive.part" $url
        if ($LASTEXITCODE -ne 0) { throw "포터블 다운로드 실패" }
        Move-Item "$archive.part" $archive
    }
    $sevenZip = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    Say "  압축 해제 중..."
    if ($sevenZip) { & $sevenZip x $archive "-o$Drive\" -aos | Out-Null }
    else { & tar.exe -xf $archive -C "$Drive\" }   # Windows 11 tar(libarchive)는 .7z 지원
    if (-not (Test-Path (Join-Path $PortableDir "ComfyUI\main.py"))) {
        throw "압축 해제 실패. 7-Zip(https://www.7-zip.org)으로 $archive 를 $Drive\ 에 직접 풀고 다시 실행하세요."
    }
    $Comfy = Join-Path $PortableDir "ComfyUI"
    Say "  설치 완료: $PortableDir" Green
}

# ---------- 4. Anima 모델 (필요한 3개만) ----------
Say "`n[4] Anima 모델 확인/다운로드 (기존 파일은 덮어쓰지 않음)" Cyan
foreach ($m in $Models) {
    $dir = Join-Path $Comfy ("models\" + $m.Sub)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dst = Join-Path $dir $m.Name
    if (Test-Path $dst) { Say "  이미 있음, 건너뜀: $dst" Green; continue }
    $url = "$HF/$($m.Sub)/$($m.Name)"
    Say "  다운로드: $url"
    & curl.exe -L --fail --retry 3 -C - -o "$dst.part" $url
    if ($LASTEXITCODE -ne 0) { throw "다운로드 실패: $url" }
    if ($m.Sha256) {
        $h = (Get-FileHash "$dst.part" -Algorithm SHA256).Hash.ToLower()
        if ($h -ne $m.Sha256) { throw "SHA256 불일치($h). 파일을 $dst.part 로 남겨두고 중단합니다." }
        Say "  SHA256 일치" Green
    }
    Move-Item "$dst.part" $dst
    Say ("  완료: {0} ({1:N2} GB)" -f $dst, ((Get-Item $dst).Length / 1GB)) Green
}

# ---------- 5. 워크플로 / 테스트 도구 / 바로가기 ----------
Say "`n[5] 워크플로 저장 및 실행 바로가기 생성" Cyan
$wfDir = Join-Path $Comfy "user\default\workflows"
New-Item -ItemType Directory -Force -Path $wfDir, "$WorkDir\input", "$WorkDir\results", "$WorkDir\tools\workflows", "$WorkDir\tools\scripts" | Out-Null
function Copy-NoOverwrite($src, $dst) {
    if (Test-Path $dst) {
        if ((Get-FileHash $src).Hash -eq (Get-FileHash $dst).Hash) { return }
        $dst = [IO.Path]::Combine([IO.Path]::GetDirectoryName($dst), [IO.Path]::GetFileNameWithoutExtension($dst) + "_" + (Get-Date -Format yyyyMMdd_HHmmss) + [IO.Path]::GetExtension($dst))
    }
    Copy-Item $src $dst; Say "  저장: $dst"
}
Copy-NoOverwrite (Join-Path $Here "workflows\Anima_img2img_denoise0.1.json") (Join-Path $wfDir "Anima_img2img_denoise0.1.json")
Copy-NoOverwrite (Join-Path $Here "workflows\Anima_img2img_denoise0.1.json") "$WorkDir\tools\workflows\Anima_img2img_denoise0.1.json"
Copy-NoOverwrite (Join-Path $Here "workflows\Anima_img2img_denoise0.1_api.json") "$WorkDir\tools\workflows\Anima_img2img_denoise0.1_api.json"
Copy-NoOverwrite (Join-Path $Here "scripts\test_anima.py") "$WorkDir\tools\scripts\test_anima.py"

$base = Split-Path -Parent $Comfy
$py = Join-Path $base "python_embeded\python.exe"
$runBat = if ($nvidia -and (Test-Path (Join-Path $base "run_nvidia_gpu.bat"))) { "run_nvidia_gpu.bat" }
          elseif (Test-Path (Join-Path $base "run_amd_gpu.bat")) { "run_amd_gpu.bat" } else { "run_cpu.bat" }
@"
@echo off
rem Start ComfyUI (Anima workflow: Workflows menu > Anima_img2img_denoise0.1)
cd /d "$base"
start "" http://127.0.0.1:8188
call "$runBat"
"@ | Set-Content -Encoding Default "$WorkDir\Start_Anima_ComfyUI.bat"
@"
@echo off
rem Drag one image onto this file (ComfyUI must be running). Original is not modified.
if "%~1"=="" ( echo Drag an image file onto this .bat & pause & exit /b 1 )
"$py" -I "$WorkDir\tools\scripts\test_anima.py" --input "%~1" --comfy-root "$Comfy" --out "$WorkDir\results"
pause
"@ | Set-Content -Encoding Default "$WorkDir\Test_Anima_img2img.bat"
if (-not (Test-Path $py)) { Say "  주의: $py 없음 - 테스트 bat의 python 경로를 직접 수정하세요." Yellow }

$ws = New-Object -ComObject WScript.Shell
$desk = [Environment]::GetFolderPath("Desktop")
foreach ($s in @(@{N = "Anima ComfyUI 실행"; T = "$WorkDir\Start_Anima_ComfyUI.bat"}, @{N = "Anima 테스트 (이미지 끌어놓기)"; T = "$WorkDir\Test_Anima_img2img.bat"})) {
    $lnk = Join-Path $desk ($s.N + ".lnk")
    if (Test-Path $lnk) { continue }
    $sc = $ws.CreateShortcut($lnk); $sc.TargetPath = $s.T; $sc.WorkingDirectory = $WorkDir; $sc.Save()
    Say "  바로가기: $lnk"
}

Say "`n설치 단계 완료. 아직 '실행 확인'은 아닙니다:" Cyan
Say "  1) 바탕화면 'Anima ComfyUI 실행' -> 브라우저에서 Workflows > Anima_img2img_denoise0.1 열기"
Say "  2) 테스트 이미지 하나를 'Anima 테스트' 바로가기에 끌어놓기 -> 결과/비교: $WorkDir\results"
