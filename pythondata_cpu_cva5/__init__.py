import os.path
__dir__ = os.path.split(os.path.abspath(os.path.realpath(__file__)))[0]
data_location = os.path.join(__dir__, "system_verilog")
src = "https://github.com/openhwgroup/cva5"

# Module version
version_str = "0.0.post639"
version_tuple = (0, 0, 639)
try:
    from packaging.version import Version as V
    pversion = V("0.0.post639")
except ImportError:
    pass

# Data version info
data_version_str = "0.0.post503"
data_version_tuple = (0, 0, 503)
try:
    from packaging.version import Version as V
    pdata_version = V("0.0.post503")
except ImportError:
    pass
data_git_hash = "b4d6a9fa2996c9bc1e9955afe5aefa9803be4993"
data_git_describe = "v0.0-503-gb4d6a9f"
data_git_msg = """\
commit b4d6a9fa2996c9bc1e9955afe5aefa9803be4993
Merge: 14c4be9 b2e425a
Author: Mike Thompson <mike@openhwgroup.org>
Date:   Mon May 16 15:19:30 2022 -0400

    Merge pull request #4 from e-matthews/litex
    
    Fetch and Load-Store Interface Refactor and LiteX Support

"""

# Tool version info
tool_version_str = "0.0.post136"
tool_version_tuple = (0, 0, 136)
try:
    from packaging.version import Version as V
    ptool_version = V("0.0.post136")
except ImportError:
    pass


def data_file(f):
    """Get absolute path for file inside pythondata_cpu_cva5."""
    fn = os.path.join(data_location, f)
    fn = os.path.abspath(fn)
    if not os.path.exists(fn):
        raise IOError("File {f} doesn't exist in pythondata_cpu_cva5".format(f))
    return fn
