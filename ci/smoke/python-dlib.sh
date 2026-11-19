# The module imports and was built for the python that Arch ships now.
python -c 'import dlib, sys; print("dlib", dlib.__version__, "on python", sys.version.split()[0])'
pacman -Qlq python-dlib | grep -q "^/usr/lib/python$(python -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')/site-packages/"
