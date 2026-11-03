# holybro-build-image

Holybro Pixhawk Jetson Baseboard에 Jetson Orin NX를 설치할 **플래시 이미지를 만드는** 스크립트입니다. 보드에 쓰지는 않습니다. 쓰기는 [holybro-flash-image](https://github.com/JunghanShin/holybro-flash-image)가 합니다.

생성과 쓰기를 나눈 이유는 USB 연결 시간입니다. 한 번에 생성하고 쓰면 보드를 USB로 연결한 채 오래 기다려야 하고, 그동안 USB write 에러가 납니다. 이 스크립트는 **보드 없이** 이미지를 만들고, 보드는 마지막 쓰기 단계에서만 연결합니다.

```text
holybro-build-image.sh   (보드 없이, 오래 걸림)
  다운로드 → 압축 해제 → NVIDIA 바이너리 적용 → Holybro 패치 → 이미지 생성
        │ 작업 폴더/Linux_for_Tegra/tools/kernel_flash/images/
        ▼
holybro-flash-image.sh   (보드 REC 모드, USB 연결)
  생성된 이미지를 NVMe와 QSPI에 쓰기
```

| 항목 | 값 |
|---|---|
| 모듈 | Jetson Orin NX |
| 캐리어 보드 | Holybro Pixhawk Jetson Baseboard |
| 소프트웨어 | JetPack 6.2.2 (L4T r36.5), Ubuntu 22.04 |
| L4T 대상 이름 | `jetson-orin-nano-devkit-super` (Orin NX도 이 이름 사용) |
| 설치 위치 | NVMe SSD (`nvme0n1p1`), 부트로더는 QSPI |

## 준비

| 항목 | 내용 |
|---|---|
| PC | x86_64 Ubuntu 22.04 (네이티브 설치 권장) |
| 권한 | `sudo` (스크립트가 필요할 때 스스로 `sudo`로 다시 실행) |
| 디스크 | 작업 폴더에 여유 공간 약 40GB |
| 인터넷 | NVIDIA BSP, 루트 파일 시스템, Holybro 패치 다운로드 (약 2.5GB) |

WSL2와 가상 머신에서는 USB 복구 장치 연결이 불안정해 권장하지 않습니다. 생성 단계는 보드가 없어도 되므로 WSL2에서도 될 수 있지만 시험하지 않았습니다.

## 설치

```bash
git clone https://github.com/JunghanShin/holybro-build-image.git
```
```bash
git clone https://github.com/JunghanShin/holybro-flash-image.git
```

## 작업 폴더

다운로드 파일, `Linux_for_Tegra`, 생성된 이미지는 모두 **작업 폴더**에 저장됩니다. 두 스크립트가 같은 작업 폴더를 써야 쓰기 스크립트가 이미지를 찾습니다.

- `-w 폴더`로 지정합니다.
- 지정하지 않으면 환경 변수 `WORK_DIR`, 그것도 없으면 **명령을 실행한 현재 폴더**를 씁니다.

아래 예시는 `~/holybro-work`를 작업 폴더로 씁니다.

## 사용법

### 1. 처음 한 번: 보드를 연결하고 생성 (`--with-board`)

보드 없이 생성하려면 보드 식별값이 필요합니다. `BOARDID`, `FAB`, `BOARDSKU`, `BOARDREV`, `CHIP_SKU`, `FUSELEVEL`은 운용 중인 보드에서 읽어 스크립트에 넣어 두었습니다. `RAMCODE_ID`만은 메모리 스트랩 핀 값이라 부팅된 보드에서 보이지 않으므로, **처음 한 번만** 보드를 REC 모드로 연결해서 생성합니다.

1. 보드 전원을 끄고 캐리어 보드의 REC 스위치를 켭니다.
2. PC와 보드의 USB-C를 연결하고 전원을 켭니다.
3. 복구 장치가 480Mbps로 잡혔는지 확인합니다. NVIDIA 장치(`0955:7323` 등)가 `480M`으로 보여야 합니다.
   ```bash
   lsusb -t
   ```
4. 생성합니다.
   ```bash
   ./holybro-build-image/holybro-build-image.sh -w ~/holybro-work --with-board
   ```
5. 끝에 보드에서 읽은 식별값이 출력됩니다(`chkbdinfo`로 `cvm.bin`, `chip_info.bin_bak`을 읽은 값). `RAMCODE_ID`를 스크립트 위쪽에 적습니다. 다른 값이 스크립트 기본값과 다르면 그것도 고칩니다.
   ```bash
   RAMCODE_ID="${RAMCODE_ID:-여기에 값}"
   ```
   값을 적으면 다음부터는 보드 없이 생성됩니다. 같은 모델의 보드라면 팀원이 이 값을 그대로 씁니다.

이 실행으로 이미지도 만들어지므로, 바로 [쓰기](#3-보드에-쓰기)로 넘어가도 됩니다.

### 2. 평소: 보드 없이 생성

```bash
./holybro-build-image/holybro-build-image.sh -w ~/holybro-work
```

- 이미지가 이미 있으면 아무것도 하지 않고 끝납니다.
- 다시 만들려면 `--force`를 붙입니다. 다운로드한 파일은 다시 받지 않습니다.
  ```bash
  ./holybro-build-image/holybro-build-image.sh -w ~/holybro-work --force
  ```
- 식별값을 스크립트에 적지 않고 환경 변수로 넘겨도 됩니다.
  ```bash
  RAMCODE_ID=값 ./holybro-build-image/holybro-build-image.sh -w ~/holybro-work
  ```

전체 출력은 작업 폴더의 `build-image.log`에 저장됩니다.

### 3. 보드에 쓰기

[holybro-flash-image](https://github.com/JunghanShin/holybro-flash-image)에서 같은 작업 폴더를 지정합니다.

```bash
./holybro-flash-image/holybro-flash-image.sh -w ~/holybro-work
```

## 옵션

| 옵션 | 설명 |
|---|---|
| `-w 폴더` | 작업 폴더 (기본: `WORK_DIR`, 없으면 현재 폴더) |
| `--force` | 기존 이미지를 지우고 다시 생성 |
| `--with-board` | REC 모드 보드(480Mbps)에서 식별값을 읽으며 생성 |
| `-h` | 사용법 출력 |

| 환경 변수 | 기본값 | 설명 |
|---|---|---|
| `BOARDID` | `3767` | 모듈 ID |
| `FAB` | `303` | 모듈 리비전 |
| `BOARDSKU` | `0000` | 모듈 SKU |
| `BOARDREV` | `F.1` | 보드 리비전 |
| `CHIP_SKU` | `00:00:00:D3` | 칩 SKU (Orin NX 16GB) |
| `FUSELEVEL` | `fuselevel_production` | 퓨즈 레벨 |
| `RAMCODE_ID` | 비어 있음 | `--with-board` 실행으로 확인 |

기본값은 운용 중인 Orin NX 16GB 보드에서 읽었습니다.

| 값 | 읽은 곳 |
|---|---|
| `BOARDID`, `FAB`, `BOARDSKU`, `BOARDREV`, `FUSELEVEL` | `/etc/nv_boot_control.conf`의 `TNSPEC 3767-303-0000-F.1-1-1` |
| `CHIP_SKU` | 커널 로그 `Tegra Revision: A01 SKU: 211` (211 = `0xD3`) |

다른 모듈(예: Orin NX 8GB)을 쓰면 `--with-board`로 다시 확인해야 합니다.

## 스크립트가 하는 일

1. 필요한 패키지를 설치합니다(`wget`, `lbzip2`, `libxml2`, `python3` 등).
2. 작업 폴더에 세 파일을 받습니다. 이미 있으면 다시 받지 않습니다.
   - `Jetson_Linux_r36.5.0_aarch64.tbz2` (NVIDIA BSP)
   - `Tegra_Linux_Sample-Root-Filesystem_r36.5.0_aarch64.tbz2` (루트 파일 시스템)
   - `holybro_jp622.tbz2` (Holybro 캐리어 보드 패치)
3. BSP와 루트 파일 시스템을 풀고 `l4t_flash_prerequisites.sh`, `apply_binaries.sh`를 실행합니다.
4. Holybro 패치를 `Linux_for_Tegra`에 덮어씁니다.
5. `l4t_initrd_flash.sh --no-flash`로 NVMe 설치용 이미지를 만듭니다.
6. `system.img`가 생겼는지 확인합니다.

## 문제 해결

| 증상 | 원인과 조치 |
|---|---|
| `CHIP_SKU or RAMCODE_ID is not set` | `RAMCODE_ID`가 비어 있습니다. [처음 한 번](#1-처음-한-번-보드를-연결하고-생성---with-board) 절차를 따릅니다. |
| `--with-board needs the board in REC at 480 Mbps` | 보드가 REC 모드가 아니거나 USB 3.x 포트에서 다른 속도로 잡혔습니다. 다른 USB 포트나 USB 2.0 허브를 써 봅니다. |
| Holybro 패치 다운로드 실패 | 패치 주소가 Holybro 문서(GitBook)의 임시 링크라 바뀔 수 있습니다. Holybro 문서에서 JetPack 6.2.2 패치를 받아 작업 폴더에 `holybro_jp622.tbz2`로 두면 다운로드를 건너뜁니다. |
| `Image generation finished but ... system.img is missing` | `build-image.log`에서 오류를 확인합니다. |

## 상태

- 실제 Linux PC에서 이 버전(작업 폴더 옵션, 보드 없이 생성)을 아직 실행해 보지 않았습니다.
- `RAMCODE_ID`는 아직 비어 있습니다. 보드를 REC 모드로 연결해 `--with-board`로 한 번 실행해야 합니다.
