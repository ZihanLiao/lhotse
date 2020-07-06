#!/usr/bin/env bash

set -eou pipefail

LIBRIMIX_ROOT=$(pwd)/data
CORPUS_PATH=${LIBRIMIX_ROOT}/MiniLibriMix
LIBRIMIX_CSV=${CORPUS_PATH}/metadata/mixture_train_mix_both.csv
OUTPUT_PATH=${LIBRIMIX_ROOT}/librimix
DURATION=3

[[ $(uname) == 'Darwin' ]] && nj=$(sysctl -n machdep.cpu.thread_count) || nj=$(grep -c ^processor /proc/cpuinfo)

# Obtain MiniLibriMix
[ -f ${LIBRIMIX_ROOT}/MiniLibriMix.zip ] || wget https://zenodo.org/record/3871592/files/MiniLibriMix.zip -P ${LIBRIMIX_ROOT}
[ -d ${CORPUS_PATH} ] || unzip ${LIBRIMIX_ROOT}/MiniLibriMix.zip -d ${LIBRIMIX_ROOT}

# Prepare audio and supervision manifests
lhotse recipe librimix \
  --min-segment-seconds $DURATION \
  --with-precomputed-mixtures \
  ${LIBRIMIX_CSV} \
  ${OUTPUT_PATH}

for type in sources mix noise; do
  # Extract features for each type of audio file
  lhotse make-feats -j "$nj" \
    -r ${LIBRIMIX_ROOT} \
    ${OUTPUT_PATH}/audio_${type}.yml \
    ${OUTPUT_PATH}/feats_${type}
  # Create cuts out of features - cuts_mix.yml will contain pre-mixed cuts for source separation
  lhotse cut simple \
    -s ${OUTPUT_PATH}/supervisions_${type}.yml \
    ${OUTPUT_PATH}/feats_${type}/feature_manifest.yml.gz \
    ${OUTPUT_PATH}/cuts_${type}.yml.gz
done

# Prepare cuts with feature-domain mixes performed on-the-fly - clean
lhotse cut mix-by-recording-id ${OUTPUT_PATH}/cuts_sources.yml.gz ${OUTPUT_PATH}/cuts_mix_dynamic_clean.yml.gz
# Prepare cuts with feature-domain mixes performed on-the-fly - noisy
lhotse cut mix-by-recording-id ${OUTPUT_PATH}/cuts_sources.yml.gz ${OUTPUT_PATH}/cuts_noise.yml.gz ${OUTPUT_PATH}/cuts_mix_dynamic_noisy.yml.gz

# The next step is truncation - it makes sure that the cuts all have the same duration and makes them easily batchable

# Truncate the pre-mixed cuts
lhotse cut truncate \
  --max-duration $DURATION \
  --offset-type random \
  --preserve-id \
  ${OUTPUT_PATH}/cuts_mix.yml.gz ${OUTPUT_PATH}/cuts_mix_${DURATION}s.yml.gz

# Truncate the dynamically-mixed clean cuts
lhotse cut truncate \
  --max-duration $DURATION \
  --offset-type random \
  --preserve-id \
  ${OUTPUT_PATH}/cuts_mix_dynamic_clean.yml.gz ${OUTPUT_PATH}/cuts_mix_dynamic_clean_${DURATION}s.yml.gz

# Truncate the dynamically-mixed noisy cuts
lhotse cut truncate \
  --max-duration $DURATION \
  --offset-type random \
  --preserve-id \
  ${OUTPUT_PATH}/cuts_mix_dynamic_noisy.yml.gz ${OUTPUT_PATH}/cuts_mix_dynamic_noisy_${DURATION}s.yml.gz

# Processing complete - the resulting YAML mixed cut manifests can be loaded in Python to create a PyTorch dataset.