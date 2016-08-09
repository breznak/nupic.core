#!/bin/bash
# ----------------------------------------------------------------------
# Numenta Platform for Intelligent Computing (NuPIC)
# Copyright (C) 2016, Numenta, Inc.  Unless you have purchased from
# Numenta, Inc. a separate commercial license for this software code, the
# following terms and conditions apply:
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero Public License version 3 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU Affero Public License for more details.
#
# You should have received a copy of the GNU Affero Public License
# along with this program.  If not, see http://www.gnu.org/licenses.
#
# http://numenta.org/licenses/
# ----------------------------------------------------------------------

# This script builds the manylinux x86_64 wide-unicode wheel per PEP-513. It
# runs inside the manylinux1_x86_64 docker container (see
# https://github.com/pypa/manylinux). Our bootstrap script that launched the
# container has mapped its nupic.core root directory as a volume in the
# container.
#

set -o errexit
set -o xtrace

# NUPIC_CORE env var may (or may not) be expected by nupic.core build.
# TODO rename NUPIC_CORE env var to NUPIC_CORE_DIR if not needed for build
NUPIC_CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

echo "RUNNING MANYLINUX BUILD; NUPIC_CORE=${NUPIC_CORE}"

# The manylinux image provides cmake28, but doesn't symlink it to cmake
CMAKE="cmake28"
${CMAKE} --version

# manylinux provides the required gcc toolchain for building extensions
CC="gcc"
CXX="g++"

# Add the python 2.7 binaries from manylinux image to PATH, overriding system
# Python
PYBIN="/opt/python/cp27-cp27mu/bin"
PATH="${PYBIN}:${PATH}"

# Help python executable find its shared lib; unlike the community manylinux
# docker image that builds statically-linked python, our custom manylinux image
# builds python with libpython.so python library, because our current C++ tests
# of python interfaces depending on having libpython.so.
LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:$(dirname ${PYBIN})/lib"

# Install pycapnp to get the headers capnp/helpers/checkCompiler.h, etc.
${PYBIN}/pip install pycapnp==0.5.8

# Install nupic.bindings dependencies
${PYBIN}/pip install \
    -r ${NUPIC_CORE}/bindings/py/requirements.txt

# Build and install nupic.bindings

mkdir -p ${NUPIC_CORE}/build/scripts
cd ${NUPIC_CORE}/build/scripts

# Cause `find_package(PythonLibs REQUIRED)` to return the desired include
# directory
PYTHON_INCLUDE_DIR="/opt/python/cp27-cp27mu/include/python2.7"

${CMAKE} ${NUPIC_CORE} \
    -DPYTHON_LIBRARY="$(dirname ${PYBIN})/lib/libpython2.7.so" \
    -DPYTHON_INCLUDE_DIR=${PYTHON_INCLUDE_DIR} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=../release \
    -DPY_EXTENSIONS_DIR=${NUPIC_CORE}/bindings/py/nupic/bindings
make install

# Build the manylinux wheel. The resulting wheel is created in
# bindings/py/dist. Example wheel name:
# nupic.bindings-0.4.5.dev0-cp27-cp27mu-linux_x86_64.whl
cd ${NUPIC_CORE}
${PYBIN}/python setup.py bdist_wheel

# Run the nupic.core C++ tests
${PYBIN}/pip install ${NUPIC_CORE}/bindings/py/dist/nupic.bindings-0.4.5.dev0-cp27-cp27mu-linux_x86_64.whl
cd ${NUPIC_CORE}/build/release/bin
./connections_performance_test
./cpp_region_test
./helloregion
./hello_sp_tp
./prototest
./py_region_test
./unit_tests

# Run the nupic.core python tests
${PYBIN}/pip install -U pytest
${PYBIN}/py.test --verbose ${NUPIC_CORE}/bindings/py/tests
