FROM jupyter/datascience-notebook:latest
LABEL org.opencontainers.image.source="https://github.com/FAIRDataPipeline/RSECon22"
USER root

ARG FAIR_ENV

ENV FAIR_ENV=${FAIR_ENV} \
    GRANT_SUDO=yes \
    USER_HOME=/home/${NB_USER} \
    CONDA_R_LIB=/opt/conda/lib/R/library

RUN apt update && \
    apt install -y graphviz \
    default-jre \
    default-jdk \
    wget \
    unzip\
    gnuplot \
    build-essential \
    cmake \
    libjsoncpp-dev \
    curl \
    libcurl4-openssl-dev \
    libyaml-cpp-dev  \
    imagemagick

# Java
RUN wget https://services.gradle.org/distributions/gradle-7.5-bin.zip && \
    unzip gradle-*.zip && \
    cp -pr gradle-*/* /usr/local && \
    rm -r gradle-7.5 && \
    rm gradle-7.5-bin.zip && \
    mkdir temp

# Python Dependencies
WORKDIR ${USER_HOME}/temp
RUN wget https://raw.githubusercontent.com/FAIRDataPipeline/FAIR-CLI/main/pyproject.toml && \
    wget https://raw.githubusercontent.com/FAIRDataPipeline/FAIR-CLI/main/poetry.lock && \
    mamba install --quiet --yes 'poetry' && \
    mamba clean --all -f -y
RUN poetry config virtualenvs.create false \
    && poetry install --no-root --no-interaction --no-ansi

# Clone Repos and allow ambigous permissions
WORKDIR ${USER_HOME}
RUN git clone https://github.com/FAIRDataPipeline/cppSimpleModel.git && \
    git clone https://github.com/FAIRDataPipeline/DataPipeline.jl.git && \
    git clone https://github.com/FAIRDataPipeline/javaDataPipeline.git && \
    git clone https://github.com/FAIRDataPipeline/javaSimpleModel.git && \
    git clone https://github.com/FAIRDataPipeline/rSimpleModel.git && \
    git clone https://github.com/FAIRDataPipeline/rDataPipeline.git && \
    git config --global --add safe.directory ${USER_HOME}/cppSimpleModel && \
    git config --global --add safe.directory ${USER_HOME}/DataPipeline.jl && \
    git config --global --add safe.directory ${USER_HOME}/javaSimpleModel && \
    git config --global --add safe.directory ${USER_HOME}/rSimpleModel && \
    git config --global --add safe.directory ${USER_HOME}/DataPipeline.jl && \
    rm -r temp

# CPP Simple Model
WORKDIR ${USER_HOME}/cppSimpleModel
RUN cmake -Bbuild && \
    cmake --build build -j4

#Julia Simple Model
WORKDIR "${USER_HOME}/DataPipeline.jl"
RUN git checkout updated-deps && \
    julia -e 'using Pkg; Pkg.instantiate()' && \
    julia --project=examples/fdp -e 'using Pkg; Pkg.instantiate()' && \
    julia --project=examples/fdp -e 'using Pkg; Pkg.precompile()'

# Java Data Pipeline
WORKDIR "${USER_HOME}/javaDataPipeline"
RUN gradle clean && \
    gradle build

# Java Simple Model
WORKDIR "${USER_HOME}/javaSimpleModel"
RUN git checkout local_deps && \
    gradle clean && \
    gradle build

# R Simple Model
WORKDIR ${USER_HOME}/temp
RUN conda config --add channels pcgr && \
    conda config --add channels anaconda && \
    conda config --add channels bioconda && \
    mamba install --quiet --yes \
    'pkg-config' \
    'libcurl' \
    'poppler' \
    'librsvg' \
    'glib' \
    'libgit2' \
    && \
    mamba clean --all -f -y
RUN wget https://imagemagick.org/archive/ImageMagick.tar.gz && \
    tar xvzf ImageMagick.tar.gz && \
    cd ImageMagick-* && \
    ./configure --prefix=/opt/conda && \
    make && \
    make install
WORKDIR ${USER_HOME}/rSimpleModel
RUN echo 'options(stringsAsFactors = FALSE)' >> /opt/conda/lib/R/etc/Rprofile.site && \
    R -e 'install.packages("magick", lib ="/opt/conda/lib/R/library", repos="https://cloud.r-project.org/", configure.vars="INCLUDE_DIR=/opt/conda/include/ImageMagick-7")' && \
    R -e 'cat(withr::with_libpaths(new="/opt/conda/lib/R/library", devtools::install_local("/home/jovyan/rDataPipeline") ) )' && \
    R -e 'cat(withr::with_libpaths(new="/opt/conda/lib/R/library", devtools::install_local() ) )'

WORKDIR ${USER_HOME}
COPY ./Notebooks .

# Permissiona
RUN fix-permissions "${JULIA_PKGDIR}" && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"
