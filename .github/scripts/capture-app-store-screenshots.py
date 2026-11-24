import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time


BUNDLE = 'com.moyichat.moyichat'
APP = Path('build/ios/iphonesimulator/Runner.app').resolve()
OUTPUT = Path('build/app-store-screenshots').resolve()
MODEL_NAME = 'kanana-1.5-2.1b-instruct-2505-q4_k_m.gguf'
MODEL_URL = (
    'https://huggingface.co/TaeyoungLeeJack/'
    'kanana-1.5-2.1b-instruct-2505-Q4_K_M-GGUF/resolve/'
    f'9a6c4bf9e13fea91c3100a891e7312dd9911f098/{MODEL_NAME}'
)
MODEL_HASH = '62a63f912a0708d9a522f974997b5bbd4927e01d739b07fe4c55c1f545241561'
PHOTO = Path('assets/preview-groceries.png').resolve()
PHOTO_ID = '00000000000000000000000000000001'


def output(*command):
    return subprocess.check_output(command, text=True).strip()


def sim(*command):
    subprocess.run(('xcrun', 'simctl', *command), check=True)


def sim_output(*command):
    return output('xcrun', 'simctl', *command)


def select_device(devices, runtimes, types, names):
    for name in names:
        device_type = next((item for item in types if item['name'] == name), None)
        if not device_type:
            continue
        for runtime in runtimes:
            identifier = runtime['identifier']
            existing = next(
                (item for item in devices.get(identifier, []) if item['isAvailable'] and item['name'] == name),
                None,
            )
            if existing:
                return existing['udid'], name
            supported = runtime.get('supportedDeviceTypes')
            if supported and device_type['identifier'] not in {item['identifier'] for item in supported}:
                continue
            try:
                device_id = sim_output('create', name, device_type['identifier'], identifier)
            except subprocess.CalledProcessError:
                continue
            return device_id, name
    raise RuntimeError(f'No matching iOS Simulator device for {names}')


def use_model(model, destination):
    try:
        os.link(model, destination)
    except OSError:
        shutil.copy2(model, destination)


def capture(device, name, dimensions, *, first_launch):
    sim('launch', '--terminate-running-process', device, BUNDLE)
    time.sleep(60 if first_launch else 25)
    png = OUTPUT / f'{name}.png'
    jpg = OUTPUT / f'{name}.jpg'
    sim('io', device, 'screenshot', str(png))
    measured = output('sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(png))
    size = tuple(int(line.split()[-1]) for line in measured.splitlines()[1:])
    if size not in dimensions:
        raise RuntimeError(f'{name} screenshot has unexpected dimensions {size}')
    subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '96', str(png),
                    '--out', str(jpg)], check=True)
    png.unlink()


def example_task(identifier, name, question, answer, *, parent=None, photo=None):
    message = {'user': True, 'text': question}
    if photo:
        message['photoIds'] = [photo]
    task = {'id': identifier, 'name': name, 'messages': [
        message, {'user': False, 'text': answer},
    ]}
    if parent:
        task['parentId'] = parent
    return task


def capture_app(device, model, label, dimensions):
    sim('bootstatus', device, '-b')
    try:
        sim('ui', device, 'appearance', 'light')
        subprocess.run([
            'xcrun', 'simctl', 'status_bar', device, 'override', '--time', '9:41',
            '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3',
            '--batteryState', 'discharging', '--batteryLevel', '100',
        ], check=False)
        sim('install', device, str(APP))
        container = Path(sim_output('get_app_container', device, BUNDLE, 'data'))
        workspace = container / 'Library' / 'Application Support' / 'MoyiChat'
        photos = workspace / 'chat-photos'
        photos.mkdir(parents=True, exist_ok=True)
        use_model(model, workspace / MODEL_NAME)
        shutil.copy2(PHOTO, photos / PHOTO_ID)
        home = {'id': 'moyichat-start', 'messages': []}
        offline = example_task(
            'offline', '기차 여행', '기차 안에서 할 일을 가볍게 정리해 줘.',
            '1. 도착해서 갈 곳을 하나 골라요.\n2. 여행 메모를 정리해요.\n3. 쉴 시간도 남겨 둬요.',
        )
        notes = example_task(
            'notes', '회의 메모', '회의 메모를 요약해 줘. 목요일까지 초안, 금요일에 함께 검토.',
            '• 목요일까지 초안 작성\n• 금요일에 초안 함께 검토',
        )
        writing = example_task(
            'writing', '답장 초안', '“오늘 조금 늦어요”를 정중한 문자로 다듬어 줘.',
            '안녕하세요. 오늘 약속 시간보다 조금 늦을 것 같아 미리 연락드려요. 기다리게 해서 죄송합니다.',
        )
        photo = example_task(
            'photo', '장보기 메모', '사진에 있는 장보기 목록을 정리해 줘.',
            '장보기 목록이에요.\n\n- 사과 2개\n- 우유 1개', photo=PHOTO_ID,
        )
        child = example_task(
            'child', '여행 체크리스트', '이제 도착 전에 챙길 것만 알려줘.',
            '• 내릴 역과 도착 시각 확인\n• 좌석과 선반에 놓은 짐 챙기기\n• 목적지까지 이동 경로 확인',
            parent='offline',
        )
        tasks = [home, offline, notes, writing, photo, child]
        scenes = (
            [('01-offline', offline), ('02-notes', notes), ('03-writing', writing),
             ('04-photo', photo), ('05-child', child)]
            if label == 'iphone' else [('01-home', home), ('02-photo-chat', photo)]
        )
        history = workspace / 'chat.json'
        for index, (name, active) in enumerate(scenes):
            state = {'activeId': active['id'], 'tasks': tasks, 'generationSize': 'small'}
            history.write_text(json.dumps(state, ensure_ascii=False), encoding='utf-8')
            capture(device, f'{label}-{name}', dimensions, first_launch=index == 0)
            sim('terminate', device, BUNDLE)
    finally:
        subprocess.run(['xcrun', 'simctl', 'shutdown', device], check=False)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    model = Path(os.environ['RUNNER_TEMP']) / MODEL_NAME
    subprocess.run(['curl', '--fail', '--location', '--retry', '2', '--max-time', '540',
                    '--silent', '--show-error', '--output', str(model), MODEL_URL], check=True)
    checksum = output('shasum', '-a', '256', str(model)).split()[0]
    if checksum != MODEL_HASH:
        raise RuntimeError('The simulator model failed integrity verification')

    inventory = json.loads(sim_output('list', '--json'))
    runtimes = sorted(
        (item for item in inventory['runtimes'] if item['isAvailable'] and re.fullmatch(
            r'com\.apple\.CoreSimulator\.SimRuntime\.iOS-\d+(?:-\d+){1,2}', item['identifier'])),
        key=lambda item: tuple(int(part) for part in item['version'].split('.')),
        reverse=True,
    )
    device_specs = [
        ('iphone', ('iPhone 16', 'iPhone 18 Pro', 'iPhone 17 Pro', 'iPhone 17', 'iPhone 16 Pro'),
         {(1179, 2556), (1206, 2622)}),
        ('ipad', ('iPad Pro 13-inch (M5)', 'iPad Pro 13-inch (M4)', 'iPad Air 13-inch (M4)',
                  'iPad Air 13-inch (M3)', 'iPad Air 13-inch (M2)'),
         {(2064, 2752), (2048, 2732)}),
    ]
    for label, names, dimensions in device_specs:
        device, name = select_device(inventory['devices'], runtimes, inventory['devicetypes'], names)
        print(f'Capturing MoyiChat on {name}', flush=True)
        capture_app(device, model, label, dimensions)


if __name__ == '__main__':
    main()
