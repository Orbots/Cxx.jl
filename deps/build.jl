if VERSION < v"0.5-dev"
    error("Cxx requires Julia 0.5")
end

#in case we have specified the path to the julia installation
#that contains the headers etc, use that
BASE_JULIA_BIN = get(ENV, "BASE_JULIA_BIN", JULIA_HOME)
BASE_JULIA_SRC = get(ENV, "BASE_JULIA_SRC", joinpath(BASE_JULIA_BIN, "../.."))

#write a simple include file with that path
println("writing path.jl file")
s = """
const BASE_JULIA_BIN=\"$BASE_JULIA_BIN\"
export BASE_JULIA_BIN

const BASE_JULIA_SRC=\"$BASE_JULIA_SRC\"
export BASE_JULIA_SRC
"""
f = open(joinpath(dirname(@__FILE__),"path.jl"), "w")
write(f, s)
close(f)

println("Tuning for julia installation at $BASE_JULIA_BIN with sources possibly at $BASE_JULIA_SRC")

# Try to autodetect C++ ABI in use
llvm_path = is_apple() ? "libLLVM" : "libLLVM-$(Base.libllvm_version)"

llvm_lib_path = Libdl.dlpath(llvm_path)
old_cxx_abi = searchindex(open(read, llvm_lib_path),"_ZN4llvm3sys16getProcessTripleEv".data,0) != 0
old_cxx_abi && (ENV["OLD_CXX_ABI"] = "1")

llvm_config_path = joinpath(BASE_JULIA_BIN,"..","tools","llvm-config")
if isfile(llvm_config_path)
    info("Building julia source build")
    ENV["LLVM_CONFIG"] = llvm_config_path
    delete!(ENV,"LLVM_VER")
else
    info("Building julia binary build")
    ENV["LLVM_VER"] = Base.libllvm_version
    ENV["JULIA_BINARY_BUILD"] = "1"
    ENV["PATH"] = string(JULIA_HOME,":",ENV["PATH"])
end

# build Cxx for DD
ENV["CMAKE_VERSION"] = "3.6.2"
ENV["GCC_VERSION"] = "4.8.5"
ENV["PYTHON_VERSION"] = "2.7.3"
CMAKE_PACKAGE_ROOT = string(ENV["DD_TOOLS_ROOT"],"/", ENV["DD_OS"], "/package/cmake/", ENV["CMAKE_VERSION"])
GCC_PACKAGE_ROOT = string(ENV["DD_TOOLS_ROOT"],"/", ENV["DD_OS"], "/package/gcc/", ENV["GCC_VERSION"])
PYTHON_PACKAGE_ROOT = string(ENV["DD_TOOLS_ROOT"],"/", ENV["DD_OS"], "/package/python/", ENV["PYTHON_VERSION"])
# path cmake and python versions.  gcc version will be specified in BuildBootstrap.Makefile cmake command line
ENV["PATH"] = string( CMAKE_PACKAGE_ROOT,"/bin:", PYTHON_PACKAGE_ROOT,"/bin:",ENV["PATH"])
# GCC_INSTALL_PREFIX doesn't seem to be working, so we will resort to this.  
# note, I think we'll need to set this whenever we want to use Cxx package
if haskey( ENV, "LD_LIBRARY_PATH" )
    ENV["LD_LIBRARY_PATH"] = string( GCC_PACKAGE_ROOT, "/lib:", GCC_PACKAGE_ROOT, "/lib64:", ENV["LD_LIBRARY_PATH"])
else
    ENV["LD_LIBRARY_PATH"] = string( GCC_PACKAGE_ROOT, "/lib:", GCC_PACKAGE_ROOT, "/lib64")
end
run(`make -j$(Sys.CPU_CORES) -f BuildBootstrap.Makefile BASE_JULIA_BIN=$BASE_JULIA_BIN BASE_JULIA_SRC=$BASE_JULIA_SRC GCC_PACKAGE_ROOT=$GCC_PACKAGE_ROOT`)
