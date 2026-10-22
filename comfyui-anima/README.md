# ComfyUI + Anima 이미지 노이즈 정리 (img2img, denoise 0.1)

Windows PC의 **D 드라이브**에 설치·실행하도록 만든 패키지입니다.

## 설치 (PC에서)
1. 이 폴더(`comfyui-anima`)를 PC의 `D:\comfyui-anima` 등에 복사합니다.
2. `CHECK_PC.bat`: GPU, VRAM, D 드라이브 여유 공간, 기존 ComfyUI 위치만 점검합니다. 아무것도 받지 않습니다.
3. `INSTALL_Anima.bat`: 아래 작업을 합니다. 실행 정책은 이 프로세스에만 적용되고, 시스템 설정은 바꾸지 않습니다.
   - 기존 ComfyUI가 있으면 그대로 씁니다. 너무 오래돼 Anima를 지원하지 않으면 자동 업데이트하지 않고 멈춥니다.
   - 없으면 GitHub 공식 포터블(`ComfyUI_windows_portable_nvidia.7z`, 약 2.0GB)을 `D:\ComfyUI_windows_portable`에 설치합니다.
   - Hugging Face 공식 저장소에서 필요한 3개 파일만 받습니다(아래 표). 이미 있는 파일은 건너뜁니다.
   - 워크플로를 저장하고, 바탕화면에 바로가기 2개를 만듭니다.

| 파일 | 경로(ComfyUI\models\…) | 크기 |
|---|---|---|
| `split_files/diffusion_models/anima-base-v1.0.safetensors` | `diffusion_models\` | 약 4.18GB (SHA256 `bd43b7cf…a006e`로 검증) |
| `split_files/text_encoders/qwen_3_06b_base.safetensors` | `text_encoders\` | 약 1.2GB |
| `split_files/vae/qwen_image_vae.safetensors` | `vae\` | 약 0.25GB |

## 실행
- 바탕화면 **"Anima ComfyUI 실행"**을 엽니다. 브라우저가 열리면 Workflows 메뉴에서 `Anima_img2img_denoise0.1`을 선택하고 이미지를 넣은 뒤 실행합니다. 결과는 `ComfyUI\output\anima_denoise\`에 저장됩니다.
- 비교 테스트: ComfyUI를 켠 상태에서 이미지 파일 하나를 **"Anima 테스트"** 바로가기에 끌어놓습니다.
  - 원본은 읽기만 합니다. ComfyUI `input`에는 사본을 넣습니다.
  - `D:\AnimaTest\results\`에 다음 파일이 저장됩니다: 결과 이미지, `_report.txt`(크기 변화·PSNR·변화 픽셀 비율), `_side_by_side.png`, `_diff_x8.png`, `_zoom_orig_result_diff.png`(변화가 큰 영역 4곳과 중앙을 3배 확대).
  - 품질은 자동으로 판정하지 않습니다. 확대 시트에서 눈·털·옷감·선이 어떻게 바뀌었는지 직접 확인하세요.

## 워크플로 설정 (`workflows/`)
UNETLoader → CLIPLoader(type `stable_diffusion`) → VAELoader → LoadImage → VAEEncode → **KSampler (seed 0 고정, steps 2, CFG 4, sampler `er_sde`, scheduler `simple`, denoise 0.1)** → VAEDecode → SaveImage

- ComfyUI 소스 v0.42.0(2026-10-21)에서 다음을 확인했습니다: `er_sde`와 `simple`은 기본 목록에 있습니다. Anima 모델 클래스(`comfy/ldm/anima`)가 있습니다. Qwen3 0.6B 텍스트 인코더는 CLIPLoader type 값과 관계없이 Anima 인코더로 자동 인식됩니다. 지원되지 않아서 바꾼 설정은 없습니다.
- denoise 0.1과 steps 2: KSampler는 내부적으로 20단계 스케줄을 만들고 마지막 2단계만 실행합니다.
- **크기 변화 주의**: VAE 인코딩 단계에서 가로·세로가 8의 배수가 아니면 중앙 기준으로 최대 7px이 잘립니다(ComfyUI 기본 동작). 리사이즈는 하지 않습니다. 테스트 리포트가 이를 자동으로 감지합니다.
- 투명(알파) 채널은 결과에 남지 않습니다.
- 프롬프트(긍정 `masterpiece, best quality, highres` / 부정 `worst quality, low quality, blurry, jpeg artifacts, noise`)는 제가 정한 값입니다. 원문 게시글을 열람하지 못했기 때문입니다. 작성자 프롬프트가 따로 있다면 바꿔 넣으세요.

## 라이선스 요약 (CircleStone Labs Non-Commercial License + NVIDIA Open Model License, Cosmos-Predict2 파생)
- **개인 테스트·비상업적 사용**: 허용됩니다.
- **모델 자체의 상업적 이용**(유료 서비스·앱에 탑재, 수익 활동, 제3자 대상 제공, 상업용 모델 학습·증류): 허용되지 않습니다. 별도 상업 라이선스가 필요합니다(문의: tdrussell@circlestone.ai).
- **생성 결과물**: 상업적 이용을 포함해 사용할 수 있다고 명시돼 있습니다(라이선스 v1.0 문구). 다만 결과물로 경쟁 모델을 학습·파인튜닝·증류하는 것은 금지됩니다. 원본 이미지의 저작권·초상권은 별도 문제입니다.
- 공식 LICENSE.md가 v1.2로 갱신됐고, 이번에는 원문을 직접 열람하지 못했습니다. 상업적으로 쓰기 전에 https://huggingface.co/circlestone-labs/Anima/blob/main/LICENSE.md 를 직접 확인하세요.
