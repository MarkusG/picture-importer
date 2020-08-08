#!/usr/bin/env python3

import os, shutil, sys, re, getopt
import dateutil.parser
from subprocess import check_output

from exif import Image

def get_video_timestamp(path):
    output = check_output(["ffprobe", "-v", "quiet", path, "-show_entries", "format_tags=creation_time"]).decode('utf-8')
    exp = re.compile('\[FORMAT\]\nTAG:creation_time=(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d*Z)\n\[\/FORMAT\]\n')
    match = exp.match(output)
    if match is None:
        return None
    return dateutil.parser.isoparse(match.group(1))

def get_image_timestamp(path):
    with open(path, 'rb') as file:
        try:
            img = Image(file)
        except:
            return None
    try:
        dt = img.datetime_original
    except:
        return None
    split = dt.split()
    split[0] = split[0].replace(':', '-')
    return dateutil.parser.parse(" ".join(split))

# parse command line arguments

src = ""
dest = ""
i = 1
while i < len(sys.argv):
    arg = sys.argv[i]
    if arg in ("-s", "--source"):
        if i + 1 == len(sys.argv):
            print("no argument to {}".format(arg))
            sys.exit(1)
        src = sys.argv[i + 1]
        if not os.path.isdir(src):
            print("{} is not a directory".format(src))
            sys.exit(1)
    elif arg in ("-d", "--destination"):
        if i + 1 == len(sys.argv):
            print("no argument to {}".format(arg))
            sys.exit(1)
        dest = sys.argv[i + 1]
        if not os.path.isdir(dest):
            print("{} is not a directory".format(dest))
            sys.exit(1)
    i += 1

# classify files by extension
img_ext = dict()
vid_ext = dict()
oth_ext = dict()

for root, sub, files in os.walk(src):
    for file in files:
        extension = file.split('.')[-1].lower()
        path = os.path.join(root, file)
        if extension in ("jpg" "png" "dng"):
            if extension in img_ext:
                img_ext[extension].append(path)
            else:
                img_ext[extension] = [path]
        elif extension in ("mp4" "avi"):
            if extension in vid_ext:
                vid_ext[extension].append(path)
            else:
                vid_ext[extension] = [path]
        else:
            if extension in oth_ext:
                oth_ext[extension].append(path)
            else:
                oth_ext[extension] = [path]

# print import preview
print("Please wait...\n")

no_ts = 0
img_count = 0
for x in [item for sub in img_ext.values() for item in sub]:
    if get_image_timestamp(x) is None:
        no_ts += 1
    else:
        img_count += 1
        
vid_count = 0
for x in [item for sub in vid_ext.values() for item in sub]:
    if get_video_timestamp(x) is None:
        no_ts += 1
    else:
        vid_count += 1

print("{} images will be imported".format(img_count))
print("{} videos will be imported\n".format(vid_count))
print("{} files have no timestamp and will not be imported\n".format(no_ts))
print("non-image files found:")
for x in oth_ext:
    print("{}: {}".format(x, len(oth_ext[x])))

choice = input("\ncontinue? (y/n) ")
if choice != 'y':
    sys.exit(1)

for ext in img_ext:
    for path in img_ext[ext]:
        ts = get_image_timestamp(path)
        if ts is None:
            print("[\033[91mFAIL\033[0m] {} has no timestamp".format(path))
            continue
        ts_str = ts.strftime("%Y%m%d_%H%M%S")
        file = "{}.{}".format(ts_str, ext)
        dir = os.path.join(dest, ts.strftime("%Y-%m-%d"))
        try:
            os.mkdir(dir)
        except FileExistsError:
            pass
        shutil.move(path, os.path.join(dir, file))
        print("[ \033[92mOK\033[0m ] {} <- {}".format(os.path.join(dir, file), path))

for ext in vid_ext:
    for path in vid_ext[ext]:
        ts = get_video_timestamp(path)
        if ts is None:
            print("[\033[91mFAIL\033[0m] {} has no timestamp".format(path))
            continue
        ts_str = ts.strftime("%Y%m%d_%H%M%S")
        file = "{}.{}".format(ts_str, ext)
        dir = os.path.join(dest, ts.strftime("%Y-%m-%d"))
        try:
            os.mkdir(dir)
        except FileExistsError:
            pass
        shutil.move(path, os.path.join(dir, file))
        print("[ \033[92mOK\033[0m ] {} <- {}".format(os.path.join(dir, file), path))
