import os.path
__dir__ = os.path.split(os.path.abspath(os.path.realpath(__file__)))[0]
data_location = os.path.join(__dir__, "system_verilog")
src = "https://github.com/openhwgroup/cva5"

# Module version
version_str = "0.0.post645"
version_tuple = (0, 0, 645)
try:
    from packaging.version import Version as V
    pversion = V("0.0.post645")
except ImportError:
    pass

# Data version info
data_version_str = "0.0.post507"
data_version_tuple = (0, 0, 507)
try:
    from packaging.version import Version as V
    pdata_version = V("0.0.post507")
except ImportError:
    pass
data_git_hash = "3239e20360993151f435fc2f5a567e09b3f185ad"
data_git_describe = "v0.0-507-g3239e20"
data_git_msg = """\
commit 3239e20360993151f435fc2f5a567e09b3f185ad
Merge: b4d6a9f ce38554
Author: Mike Thompson <mike@openhwgroup.org>
Date:   Thu May 26 13:17:14 2022 -0400

    Merge pull request #5 from e-matthews/minor-fixes
    
    Minor fixes

"""

# Tool version info
tool_version_str = "0.0.post138"
tool_version_tuple = (0, 0, 138)
try:
    from packaging.version import Version as V
    ptool_version = V("0.0.post138")
except ImportError:
    pass


def data_file(f):
    """Get absolute path for file inside pythondata_cpu_cva5."""
    fn = os.path.join(data_location, f)
    fn = os.path.abspath(fn)
    if not os.path.exists(fn):
        raise IOError("File {f} doesn't exist in pythondata_cpu_cva5".format(f))
    return fn
