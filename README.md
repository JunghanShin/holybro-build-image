# holybro-build-image

Holybro Pixhawk Jetson Baseboard에 Jetson Orin NX를 설치할 **플래시 이미지를 만드는** 스크립트입니다. 보드에 쓰지는 않습니다. 쓰기는 [holybro-flash-image](https://github.com/JunghanShin/holybro-flash-image)가 합니다.

이미지에는 **JetPack 6.2.2 런타임**(CUDA, TensorRT, cuDNN, VPI, OpenCV 등)과 **기본 사용자 계정**이 들어 있어, 플래시하고 전원만 켜면 바로 SSH로 접속해 쓸 수 있습니다. 런타임 버전은 크로스 컴파일 환경 [jetson-dev-env](https://github.com/JunghanShin/jetson-dev-env)와 같은 목록(`jetpack-6.2.2.list`)으로 고정되어, PC에서 빌드한 프로그램이 그대로 실행됩니다.

생성과 쓰기를 나눈 이유는 USB 연결 시간입니다. 한 번에 생성하고 쓰면 보드를 USB로 연결한 채 오래 기다려야 하고, 그동안 USB write 에러가 납니다. 이 스크립트는 **보드 없이** 이미지를 만들고, 보드는 마지막 쓰기 단계에서만 연결합니다.

```text
holybro-build-image.sh   (보드 없이, 오래 걸림)
  다운로드 → 압축 해제 → NVIDIA 바이너리 적용 → Holybro 패치
  → JetPack 런타임 설치 → 언어·시간대·키보드 → 기본 사용자 → 이미지 생성
        │ 작업 폴더/Linux_for_Tegra/tools/kernel_flash/images/
        ▼
holybro-flash-image.sh   (보드 REC 모드, USB 연결)
  생성된 이미지를 NVMe와 QSPI에 쓰기
```

| 항목 | 값 |
|---|---|
| 모듈 | Jetson Orin NX |
| 캐리어 보드 | Holybro Pixhawk Jetson Baseboard |
| 소프트웨어 | JetPack 6.2.2 (L4T 36.5.0), Ubuntu 22.04. Holybro 패치(`holybro_jp622`)가 지원하는 버전 |
| L4T 대상 이름 | `jetson-orin-nano-devkit-super` (Orin NX도 이 이름 사용) |
| 설치 위치 | NVMe SSD (`nvme0n1p1`), 부트로더는 QSPI |

## 준비

| 항목 | 내용 |
|---|---|
| PC | x86_64 Ubuntu 22.04 (네이티브 설치 권장) |
| 권한 | `sudo` (스크립트가 필요할 때 스스로 `sudo`로 다시 실행) |
| 디스크 | 작업 폴더에 여유 공간 약 50GB |
| 인터넷 | NVIDIA BSP, 루트 파일 시스템, Holybro 패치(약 2.5GB)와 JetPack 런타임 패키지(수 GB) 다운로드 |

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

### 1. 이미지 생성 (보드 없이)

보드 식별값은 모두 스크립트에 들어 있으므로 보드를 연결하지 않고 생성합니다.

```bash
./holybro-build-image/holybro-build-image.sh -w ~/holybro-work
```

- 이미지가 이미 있으면 아무것도 하지 않고 끝납니다.
- 다시 만들려면 `--force`를 붙입니다. 다운로드한 파일은 다시 받지 않습니다.
  ```bash
  ./holybro-build-image/holybro-build-image.sh -w ~/holybro-work --force
  ```

전체 출력은 작업 폴더의 `build-image.log`에 저장됩니다.

### 2. 보드에 쓰기

[holybro-flash-image](https://github.com/JunghanShin/holybro-flash-image)에서 같은 작업 폴더를 지정합니다.

```bash
./holybro-flash-image/holybro-flash-image.sh -w ~/holybro-work
```

### 3. 첫 부팅과 접속

초기 설정 화면 없이 바로 부팅되고 자동 로그인됩니다. 모니터 없이 SSH로 접속합니다.

| 항목 | 값 |
|---|---|
| 사용자 / 비밀번호 | `dev` / `roqkf` |
| 호스트 이름 | `jetson` |
| 언어 / 키보드 | 영어 `en_US.UTF-8` / US |
| 시간대 | `Asia/Seoul` |

- **USB-C로 접속:** 보드와 PC를 USB-C로 연결하면 USB 네트워크가 잡히고, 보드 주소는 `192.168.55.1`입니다.
  ```bash
  ssh dev@192.168.55.1
  ```
- **이더넷:** 기본은 DHCP입니다. 공유기에서 받은 IP로 접속합니다.
- 런타임이 들어갔는지 확인합니다. `6.2.2+b24`가 나와야 합니다.
  ```bash
  dpkg-query -W nvidia-jetpack-runtime
  ```

고정 IP, 프로젝트 프로그램과 서비스는 이미지에 들어 있지 않습니다. 각 프로젝트의 설치 절차를 따릅니다.

### 다른 모듈을 쓸 때: 보드 식별값 다시 확인 (`--with-board`)

스크립트의 식별값은 우리 Orin NX 16GB 보드 값입니다. 다른 모듈(예: Orin NX 8GB)을 쓰면 그 보드에서 한 번 읽어야 합니다. 보드에는 아무것도 쓰지 않습니다.

1. 보드 전원을 끄고 캐리어 보드의 REC 스위치를 켭니다.
2. PC와 보드의 USB-C를 연결하고 전원을 켭니다.
3. 복구 장치가 480Mbps로 잡혔는지 확인합니다. NVIDIA 장치(`0955:7323` 등)가 `480M`으로 보여야 합니다.
   ```bash
   lsusb -t
   ```
4. 보드를 읽으며 생성합니다.
   ```bash
   ./holybro-build-image/holybro-build-image.sh -w ~/holybro-work --with-board --force
   ```
5. 끝에 보드에서 읽은 식별값(`BOARDID` ~ `RAMCODE_ID`)이 출력됩니다. 스크립트 기본값과 다른 값을 스크립트 위쪽에 고쳐 적습니다. 스크립트를 고치지 않고 환경 변수로 넘겨도 됩니다.
   ```bash
   BOARDSKU=0001 CHIP_SKU=00:00:00:D4 ./holybro-build-image/holybro-build-image.sh -w ~/holybro-work
   ```

이미지 생성 없이 값만 빨리 보려면, 준비된 `Linux_for_Tegra`에서 아래를 실행합니다(몇 분). 출력의 `Ram code`, `Chip sku`, `Board ID(...) version(...) sku(...) revision(...)`이 식별값입니다. 마지막에 SD 카드 관련 `Error`가 나와도 값은 이미 다 읽은 뒤라 무시해도 됩니다.
```bash
sudo ./flash.sh --no-flash --no-systemimg jetson-orin-nano-devkit-super nvme0n1p1
```

끝나면 전원을 끄고 REC 스위치를 원래대로 돌린 뒤 켜면 SSD의 기존 시스템으로 부팅됩니다.

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
| `RAMCODE_ID` | `00:00:00:01` | DRAM 종류 (RAMCODE 1) |
| `JETSON_USER` | `dev` | 기본 사용자 |
| `JETSON_PASSWORD` | `roqkf` | 기본 사용자 비밀번호 |
| `JETSON_HOSTNAME` | `jetson` | 호스트 이름 |
| `JETSON_TIMEZONE` | `Asia/Seoul` | 시간대 |

기본값은 운용 중인 Orin NX 16GB 보드에서 읽었습니다.

| 값 | 읽은 곳 |
|---|---|
| `BOARDID`, `FAB`, `BOARDSKU`, `BOARDREV`, `FUSELEVEL` | `/etc/nv_boot_control.conf`의 `TNSPEC 3767-303-0000-F.1-1-1` |
| `CHIP_SKU` | 커널 로그 `Tegra Revision: A01 SKU: 211` (211 = `0xD3`) |
| `RAMCODE_ID` | REC 모드에서 `flash.sh --no-flash` 실행 출력 `Ram code: 0x1` |

다른 모듈(예: Orin NX 8GB)을 쓰면 `--with-board`로 다시 확인해야 합니다.

## 스크립트가 하는 일

1. 필요한 패키지를 설치합니다(`wget`, `lbzip2`, `libxml2`, `python3`, `qemu-user-static` 등).
2. 작업 폴더에 세 파일을 받습니다. 이미 있으면 다시 받지 않습니다.
   - `Jetson_Linux_r36.5.0_aarch64.tbz2` (NVIDIA BSP)
   - `Tegra_Linux_Sample-Root-Filesystem_r36.5.0_aarch64.tbz2` (루트 파일 시스템)
   - `holybro_jp622.tbz2` (Holybro 캐리어 보드 패치)
3. BSP와 루트 파일 시스템을 풀고 `l4t_flash_prerequisites.sh`, `apply_binaries.sh`를 실행합니다.
4. Holybro 패치를 `Linux_for_Tegra`에 덮어씁니다.
5. 루트 파일 시스템(ARM64) 안으로 `qemu-user-static`을 통해 chroot해서 `nvidia-jetpack-runtime=6.2.2+b24`를 설치합니다.
   - `jetpack-6.2.2.list`의 버전으로 모든 JetPack 패키지를 고정합니다. NVIDIA 저장소에는 JetPack 6.2.3도 있어서 고정하지 않으면 다른 버전이 설치됩니다.
   - L4T 패키지(`nvidia-l4t-*`)는 BSP 버전(36.5.0)으로 고정합니다. 커널과 부트로더는 BSP에서 오므로 L4T 패키지만 올리면 서로 어긋납니다.
   - 이미지의 L4T 버전이 목록과 다르면 멈춥니다.
   - 고정 설정은 보드의 `/etc/apt/preferences.d/jetpack-6.2.2.pref`에 남습니다. 보드에서 `apt upgrade`를 해도 이 버전에 머뭅니다. 새 JetPack으로 올리려면 이 파일을 지웁니다.
6. 언어(`en_US.UTF-8`), 키보드(US), 시간대를 설정합니다.
7. NVIDIA의 `l4t_create_default_user.sh`로 기본 사용자를 만들고 자동 로그인을 켭니다. 첫 부팅 초기 설정 화면(oem-config)이 나오지 않습니다.
   - 같은 이름의 사용자가 이미 있으면(다시 실행할 때) 사용자는 그대로 두고 초기 설정 화면만 다시 끕니다. `apply_binaries.sh`가 실행될 때마다 초기 설정 화면을 다시 켜기 때문입니다.
   - 이미지를 만들기 전에 초기 설정 화면이 꺼져 있는지 확인하고, 켜져 있으면 멈춥니다.
8. `l4t_initrd_flash.sh --no-flash`로 NVMe 설치용 이미지를 만듭니다.
9. `system.img`가 생겼는지 확인합니다.

## 문제 해결

| 증상 | 원인과 조치 |
|---|---|
| `CHIP_SKU or RAMCODE_ID is not set` | 식별값을 비워서 실행했습니다. [다른 모듈을 쓸 때](#다른-모듈을-쓸-때-보드-식별값-다시-확인---with-board) 절차로 값을 확인합니다. |
| `--with-board needs the board in REC at 480 Mbps` | 보드가 REC 모드가 아니거나 USB 3.x 포트에서 다른 속도로 잡혔습니다. 다른 USB 포트나 USB 2.0 허브를 써 봅니다. |
| Holybro 패치 다운로드 실패 | 패치 주소가 Holybro 문서(GitBook)의 임시 링크라 바뀔 수 있습니다. Holybro 문서에서 JetPack 6.2.2 패치를 받아 작업 폴더에 `holybro_jp622.tbz2`로 두면 다운로드를 건너뜁니다. |
| `Image generation finished but ... system.img is missing` | `build-image.log`에서 오류를 확인합니다. |
| 플래시 후 `OEM installation` / System Configuration 화면이 나옴 | 이전 버전 스크립트로 두 번 이상 실행한 이미지입니다. 최신 스크립트로 `--force` 생성 후 다시 플래시합니다. 이미 플래시한 보드는 `Ctrl+Alt+F3`에서 로그인해 `sudo rm /etc/systemd/system/default.target && sudo reboot`로 끌 수 있습니다. |
| `L4T in the image is ... but ... expects ...` | BSP와 `jetpack-6.2.2.list`의 L4T 버전이 다릅니다. BSP나 목록 중 하나를 바꿨다면 둘을 같은 JetPack 버전으로 맞춥니다. |
| 런타임 설치 중 `exec format error` | ARM64 실행용 `qemu-user-static`/`binfmt` 등록이 안 됐습니다. `sudo systemctl restart systemd-binfmt` 후 다시 실행합니다. |

## JetPack 버전을 바꿀 때

버전은 Holybro 패치가 지원하는 JetPack을 기준으로 정합니다. 바꿀 때는 아래를 함께 바꿉니다.

1. 스크립트의 `BSP_URL`, `ROOTFS_URL`, `PATCH_URL`(새 JetPack용 Holybro 패치)
2. 스크립트의 `JETPACK_VERSION`, `PIN_LIST`
3. 새 버전 목록 파일. jetson-dev-env의 `docker/jetpack-*.list`와 **같은 파일**이어야 합니다. 두 저장소가 서로 의존하지 않도록 복사해 둡니다.

## 상태

- 실제 Linux PC에서 이 버전(작업 폴더, 보드 없이 생성, 런타임·사용자 설치)을 아직 실행해 보지 않았습니다.
- 보드 식별값은 모두 확인했습니다(REC 모드에서 읽은 값과 일치).
