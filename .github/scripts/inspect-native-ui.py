import json,sys,zipfile
from pathlib import Path
source=next(Path(sys.argv[1]).glob('*.ipa'));out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
selected={11:'Gameplay',12:'CinematicOverlay',23:'Main',27:'Tutorial',28:'Library_Common',54:'TopBar'}
with zipfile.ZipFile(source) as z:
 for number,name in selected.items():
  raw=z.read(f'Payload/Spiderman.app/data_final/file{number:06d}.dat');assert raw[:3]==b'GYV'
  (out/f'{name}.swf').write_bytes(b'FWS'+raw[3:])
print('Extracted six indexed native UI movies; only diagnostic copies have standard SWF signatures.')
