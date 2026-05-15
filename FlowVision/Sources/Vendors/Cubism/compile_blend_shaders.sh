#!/bin/bash

SHADER_DIR=${SRCROOT}/FlowVision/Sources/Vendors/Cubism/Framework/Rendering/Metal/Shaders
OUTPUT_DIR=${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Resources/FrameworkMetallibs

mkdir -p ${OUTPUT_DIR}
mkdir -p ${DERIVED_FILE_DIR}

xcrun metal -c ${SHADER_DIR}/MetalShaders.metal -I ${SHADER_DIR} -o ${DERIVED_FILE_DIR}/MetalShaders.air
xcrun metallib ${DERIVED_FILE_DIR}/MetalShaders.air -o ${OUTPUT_DIR}/MetalShaders.metallib

xcrun metal -c ${SHADER_DIR}/VertShaderSrcBlend.metal -I ${SHADER_DIR} -o ${DERIVED_FILE_DIR}/VertShaderSrcBlend.air || true
xcrun metallib ${DERIVED_FILE_DIR}/VertShaderSrcBlend.air -o ${OUTPUT_DIR}/VertShaderSrcBlend.metallib || true

xcrun metal -c ${SHADER_DIR}/VertShaderSrcMaskedBlend.metal -I ${SHADER_DIR} -o ${DERIVED_FILE_DIR}/VertShaderSrcMaskedBlend.air || true
xcrun metallib ${DERIVED_FILE_DIR}/VertShaderSrcMaskedBlend.air -o ${OUTPUT_DIR}/VertShaderSrcMaskedBlend.metallib || true

COLOR_NAMES=(Normal Add AddGlow Darken Multiply ColorBurn LinearBurn Lighten Screen ColorDodge Overlay SoftLight HardLight LinearLight Hue Color)
COLOR_VALS=(0 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17)
ALPHA_NAMES=(Over Atop Out ConjointOver DisjointOver)
ALPHA_VALS=(0 1 2 3 4)
FRAG_BASES=(FragShaderSrcBlend FragShaderSrcMaskBlend FragShaderSrcMaskInvertedBlend FragShaderSrcPremultipliedAlphaBlend FragShaderSrcMaskPremultipliedAlphaBlend FragShaderSrcMaskInvertedPremultipliedAlphaBlend)

ci=0
while [ $ci -lt 16 ]; do
    color=${COLOR_NAMES[$ci]}
    cidx=${COLOR_VALS[$ci]}
    astart=0
    if [ $ci -eq 0 ]; then astart=1; fi
    ai=$astart
    while [ $ai -lt 5 ]; do
        alpha=${ALPHA_NAMES[$ai]}
        aidx=${ALPHA_VALS[$ai]}
        fi2=0
        while [ $fi2 -lt 6 ]; do
            fbase=${FRAG_BASES[$fi2]}
            oname=${fbase}${color}${alpha}
            xcrun metal -c ${SHADER_DIR}/${fbase}.metal -I ${SHADER_DIR} -DCSM_COLOR_BLEND_MODE=${cidx} -DCSM_ALPHA_BLEND_MODE=${aidx} -o ${DERIVED_FILE_DIR}/${oname}.air 2>/dev/null || true
            xcrun metallib ${DERIVED_FILE_DIR}/${oname}.air -o ${OUTPUT_DIR}/${oname}.metallib 2>/dev/null || true
            fi2=$((fi2+1))
        done
        ai=$((ai+1))
    done
    ci=$((ci+1))
done

echo Blend shaders compiled
exit 0
