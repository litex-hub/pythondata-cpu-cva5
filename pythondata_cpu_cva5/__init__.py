import os.path
__dir__ = os.path.split(os.path.abspath(os.path.realpath(__file__)))[0]
data_location = os.path.join(__dir__, "system_verilog")
src = "https://github.com/openhwgroup/cva5"

# Module version
version_str = "0.0.post649"
version_tuple = (0, 0, 649)
try:
    from packaging.version import Version as V
    pversion = V("0.0.post649")
except ImportError:
    pass

# Data version info
data_version_str = "0.0.post579"
data_version_tuple = (0, 0, 579)
try:
    from packaging.version import Version as V
    pdata_version = V("0.0.post579")
except ImportError:
    pass
data_git_hash = "101987c502602e06b9162e76a1042dc33ec2ffdb"
data_git_describe = "v0.9-579-g101987c"
data_git_msg = """\
commit 101987c502602e06b9162e76a1042dc33ec2ffdb
Merge: 4efa1e2d0326ad1cc9d957b313cd2b4f3b4b7ae4
Author: mohammadshahidzade <48639781+mohammadshahidzade@users.noreply.github.com>
Date: Mon Mar 17 20:19:22 2025 -0700

    adding the marchid (#30)


"""

# Tool version info
tool_version_str = "0.0.post142"
tool_version_tuple = (0, 0, 142)
try:
    from packaging.version import Version as V
    ptool_version = V("0.0.post142")
except ImportError:
    pass


def data_file(f):
    """Get absolute path for file inside pythondata_cpu_cva5."""
    fn = os.path.join(data_location, f)
    fn = os.path.abspath(fn)
    if not os.path.exists(fn):
        raise IOError("File {f} doesn't exist in pythondata_cpu_cva5".format(f))
    return fn
