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


def capture(device, name, dimensions):
    sim('launch', '--terminate-running-process', device, BUNDLE)
    time.sleep(20)
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


def capture_app(device, model, label, dimensions):
    sim('bootstatus', device, '-b')
    try:
        sim('ui', device, 'appearance', 'light')
        sim('status_bar', device, 'override', '--time', '9:41', '--dataNetwork', 'wifi',
            '--wifiMode', 'active', '--wifiBars', '3', '--batteryState', 'unplugged',
            '--batteryLevel', '100')
        sim('install', device, str(APP))
        container = Path(sim_output('get_app_container', device, BUNDLE, 'data'))
        workspace = container / 'Library' / 'Application Support' / 'MoyiChat'
        photos = workspace / 'chat-photos'
        photos.mkdir(parents=True, exist_ok=True)
        use_model(model, workspace / MODEL_NAME)
        shutil.copy2(PHOTO, photos / PHOTO_ID)
        primary = {'id': 'moyichat-start', 'messages': []}
        example = {'id': 'moyichat-example', 'name': '장보기 메모', 'messages': [
            {'user': True, 'text': '사진에 있는 장보기 목록을 정리해 줘.', 'photoIds': [PHOTO_ID]},
            {'user': False, 'text': '장보기 목록이에요.\n\n- 사과 2개\n- 우유 1개'},
        ]}
        state = {'activeId': primary['id'], 'tasks': [primary, example], 'generationSize': 'small'}
        history = workspace / 'chat.json'
        history.write_text(json.dumps(state, ensure_ascii=False), encoding='utf-8')
        capture(device, f'{label}-01-home', dimensions)
        sim('terminate', device, BUNDLE)
        state['activeId'] = example['id']
        history.write_text(json.dumps(state, ensure_ascii=False), encoding='utf-8')
        capture(device, f'{label}-02-photo-chat', dimensions)
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
