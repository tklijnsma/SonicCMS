#!/bin/bash
(
    # Run setup script in subshell
    # Set debugging options, that should always cleanup
    trap cleanup EXIT SIGSTOP SIGHUP SIGTERM ERR
    cleanup(){
        echo "Running cleanup"
        set +euxoE
        exit
        }
    set -euxoE pipefail

    # __________________________________________________________
    # Define functions

    export SCRAM_ARCH=slc6_amd64_gcc700
    export CMSSWVER=CMSSW_10_2_0

    setup_cmssw(){
        scram project ${CMSSWVER}
        }

    activate_cmssw(){
        cd ${CMSSWVER}
        eval `scramv1 runtime -sh`
        }

    set_vars_after_cmssw(){
        unset PYTHONPATH
        export CMSSWTF=$(dirname $(python3 -c "import tensorflow; print(tensorflow.__file__)"))
        export WORK=$CMSSW_BASE/work
        mkdir -p "${WORK}/local"
        }

    install_grpc(){
        cd $WORK
        git clone https://github.com/grpc/grpc -b v1.14.0
        cd grpc
        git submodule update --init
        make -j 8
        # get ldconfig
        if ! [ type ldconfig >& /dev/null ]; then
            export PATH=${PATH}:/sbin
        fi
        # get around "make: execvp: /bin/sh: Argument list too long" if directory path is long
        ln -s $CMSSW_BASE base
        make install prefix=base/work/local/grpc
        # link libraries because tensorflow_serving tries to get the wrong versions for some reason
        cd $CMSSW_BASE/work/local/grpc/lib
        ln -s libgrpc++.so.1.14.0 libgrpc++.so.1
        ln -s libgrpc++_reflection.so.1.14.0 libgrpc++_reflection.so.1

        # setup in scram
        cat << 'EOF_TOOLFILE' > ${CMSSW_BASE}/config/toolbox/${SCRAM_ARCH}/tools/selected/grpc.xml
<tool name="grpc" version="v1.14.0">
  <info url="https://github.com/grpc/grpc"/>
  <lib name="grpc"/>
  <lib name="grpc++"/>
  <lib name="grpc++_reflection"/>
  <client>
    <environment name="GRPC_BASE" default="$CMSSW_BASE/work/local/grpc"/>
    <environment name="INCLUDE" default="$GRPC_BASE/include"/>
    <environment name="LIBDIR" default="$GRPC_BASE/lib"/>
  </client>
</tool>
EOF_TOOLFILE

        cd $CMSSW_BASE/work/local/grpc
        scram setup grpc
        }

    install_tf(){
        set -e
        cd $WORK
        git clone https://github.com/hls-fpga-machine-learning/inception_cmake
        cd inception_cmake
        git submodule update --init
        cd serving
        git checkout 1.6.1
        git clone --recursive https://github.com/tensorflow/tensorflow.git -b v1.6.0
        export PATH="/cvmfs/sft.cern.ch/lcg/contrib/CMake/3.7.0/Linux-x86_64/bin/:${PATH}"  # to get cmake
        cd ..

        mkdir build
        cd build
        # some really bad ways to get info out of scram
        PROTOBUF_LIBDIR=$(scram tool info protobuf | grep "LIBDIR=" | sed 's/LIBDIR=//')
        PROTOBUF_INCLUDE=$(scram tool info protobuf | grep "INCLUDE=" | sed 's/INCLUDE=//')
        GRPC_LIBDIR=$(scram tool info grpc | grep "LIBDIR=" | sed 's/LIBDIR=//')
        GRPC_INCLUDE=$(scram tool info grpc | grep "INCLUDE=" | sed 's/INCLUDE=//')
        GRPC_BIN=$(scram tool info grpc | grep "GRPC_BASE=" | sed 's/GRPC_BASE=//')
        TENSORFLOW_LIBDIR=$(scram tool info tensorflow | grep "LIBDIR=" | sed 's/LIBDIR=//')
        TENSORFLOW_INCLUDE=$(scram tool info tensorflow | grep "INCLUDE=" | sed 's/INCLUDE=//')
        cmake .. -DPROTOBUF_LIBRARY=$PROTOBUF_LIBDIR/libprotobuf.so -DPROTOBUF_INCLUDE_DIR=$PROTOBUF_INCLUDE -DGRPC_LIBRARY=$GRPC_LIBDIR/libgrpc.so -DGRPC_GRPC++_LIBRARY=$GRPC_LIBDIR/libgrpc++.so -DGRPC_INCLUDE_DIR=$GRPC_INCLUDE -DGRPC_GRPC++_REFLECTION_LIBRARY=$GRPC_LIBDIR/libgrpc++_reflection.so -DGRPC_CPP_PLUGIN=$GRPC_BIN/bin/grpc_cpp_plugin -DTENSORFLOW_CC_LIBRARY=$TENSORFLOW_LIBDIR/libtensorflow_cc.so -DTENSORFLOW_INCLUDE_DIR=$TENSORFLOW_INCLUDE -DEIGEN_INCLUDE_DIR=$TENSORFLOW_INCLUDE/eigen -DTENSORFLOW_FWK_LIBRARY=$TENSORFLOW_LIBDIR/libtensorflow_framework.so
        make
        # install
        mkdir $CMSSW_BASE/work/local/tensorflow_serving
        mkdir $CMSSW_BASE/work/local/tensorflow_serving/lib
        mkdir $CMSSW_BASE/work/local/tensorflow_serving/include
        cp libtfserving.so $CMSSW_BASE/work/local/tensorflow_serving/lib/
        cp -r proto-src/tensorflow_serving $CMSSW_BASE/work/local/tensorflow_serving/include/

        # setup in scram
        cat << 'EOF_TOOLFILE' > ${CMSSW_BASE}/config/toolbox/${SCRAM_ARCH}/tools/selected/tensorflow-serving.xml
<tool name="tensorflow-serving" version="1.6.1">
  <info url="https://github.com/kpedro88/inception_cmake"/>
  <lib name="tfserving"/>
  <client>
    <environment name="TFSERVING_BASE" default="$CMSSW_BASE/work/local/tensorflow_serving"/>
    <environment name="INCLUDE" default="$TFSERVING_BASE/include"/>
    <environment name="LIBDIR" default="$TFSERVING_BASE/lib"/>
  </client>
  <use name="protobuf"/>
  <use name="grpc"/>
  <use name="eigen"/>
  <use name="tensorflow-cc"/>
  <use name="tensorflow-framework"/>
</tool>
EOF_TOOLFILE

        scram setup tensorflow-serving
        }

    clone_repo(){
        cd $CMSSW_BASE/src
        git cms-init
        git clone https://github.com/hls-fpga-machine-learning/SonicCMS -b "kjp/1020_azureml_ew"
        scram b -j 8
        }

    # __________________________________________________________
    # Run the setup

    setup_cmssw
    activate_cmssw
    set_vars_after_cmssw
    install_grpc
    install_tf
    )
