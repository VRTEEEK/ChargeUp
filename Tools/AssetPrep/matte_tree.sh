#!/bin/zsh
# Gives a Meshy tree USDZ a matte, non-metallic surface for RealityKit,
# keeping its geometry, colour map and normal map exactly as they are.
#
#   Tools/AssetPrep/matte_tree.sh <in.usdz> <out.usdz> [foliage 0.85] [bark 0.9]
#
# Meshy trees come with one UsdPreviewSurface whose roughness map sits around
# 0.56 everywhere, which RealityKit renders as a glossy plastic coat, and
# with doubleSided = 1, which draws back faces behind the front ones. This:
#   - replaces the roughness map with one built by roughness_from_colour.swift
#     (foliage value on green texels, bark value elsewhere);
#   - sets metallic to a constant 0 and drops the metallic map;
#   - pins clearcoat to 0, opacity to 1 and emission to black (no transmission
#     exists in UsdPreviewSurface);
#   - sets doubleSided = 0. Only for a closed mesh with outward normals:
#     decimate_tree.py welds the tree closed; check with a surface audit
#     before trusting this on another model.
set -euo pipefail
in=$1; out=$2; foliage=${3:-0.85}; bark=${4:-0.9}
here=${0:A:h}
work=$(mktemp -d)
trap 'rm -rf $work' EXIT

swiftc -O $here/roughness_from_colour.swift -o $work/roughness_from_colour
mkdir $work/pkg && (cd $work/pkg && unzip -q $in)
cd $work/pkg
usdc=$(ls *.usdc | head -1)
colour=$(ls textures/*image_0.jpg | head -1)
rough=$(ls textures/*roughness.png | head -1)
metal=$(ls textures/*metallic.png | head -1)
$work/roughness_from_colour $colour $rough 2048 $foliage $bark

usdcat $usdc -o $work/tree.usda
# Exactly one of each line is expected; fail rather than guess.
for pattern in 'uniform bool doubleSided = 1' 'float inputs:metallic.connect' 'float inputs:clearcoat = ' 'float inputs:opacity = ' 'color3f inputs:emissiveColor = '; do
    [[ $(grep -c "$pattern" $work/tree.usda) == 1 ]] || { echo "expected one '$pattern'"; exit 1; }
done
# The texture node that fed metallic, removed below with its file.
metal_shader=$(grep 'float inputs:metallic.connect' $work/tree.usda | sed -E 's|.*/([^/.]+)\.outputs:.*|\1|')
sed -i '' \
    -e 's/uniform bool doubleSided = 1/uniform bool doubleSided = 0/' \
    -e 's/float inputs:metallic.connect = .*/float inputs:metallic = 0/' \
    -e 's/float inputs:clearcoat = .*/float inputs:clearcoat = 0/' \
    -e 's/float inputs:opacity = .*/float inputs:opacity = 1/' \
    -e 's/color3f inputs:emissiveColor = .*/color3f inputs:emissiveColor = (0, 0, 0)/' \
    $work/tree.usda
# Drop that node's block: from its def line to the brace that closes it.
awk -v name="def Shader \"$metal_shader\"" '
    skip == 0 && index($0, name) { skip = 1; depth = 0; seen = 0 }
    skip == 1 {
        n = gsub(/\{/, "{"); m = gsub(/\}/, "}")
        depth += n - m; if (n > 0) seen = 1
        if (seen && depth == 0) skip = 2
        next
    }
    { print }' $work/tree.usda > $work/tree_clean.usda
grep -q "${metal:t}" $work/tree_clean.usda && { echo "metallic map still referenced"; exit 1; }
usdcat $work/tree_clean.usda -o $usdc
rm $metal

files=($usdc $(find textures -type f | sort))
rm -f $out
usdzip $out $files >/dev/null
usdchecker $out | tail -1
echo "wrote $out"
