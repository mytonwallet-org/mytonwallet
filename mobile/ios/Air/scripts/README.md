# Scripts

## Swift Module Dependency Analysis Tools

This directory contains tools for analyzing the dependency graph of Swift modules in the MyTonWallet iOS project.

### Quick Start

```bash
# Run complete analysis with visual graph
./analyze_dependencies.sh -g

# Just show the dependency report
./analyze_dependencies.sh -n

# Generate SVG graph (better for large diagrams)
./analyze_dependencies.sh -g -f svg
```

### 🔧 Tools
- **`analyze_dependencies.sh`** - User-friendly wrapper script (start here!)
- **`build_dependency_graph.py`** - Core Python analysis engine

### 📊 Generated Output  
- **`dependency_graph.dot`** - GraphViz DOT file with clustered visualization
- **`dependency_graph.png/svg`** - Visual dependency graphs
- **`dependency_data.json`** - Structured dependency data

## Asset Usage Scanner

Use this script to find candidate unused assets in an asset catalog:

```bash
python3 mobile/ios/Air/scripts/find_unused_assets.py \
  --assets mobile/ios/Air/SubModules/WalletContext/Resources/Assets.xcassets \
  --scan-root mobile/ios/Air
```

Useful flags:
- `--with-paths` to print asset folder paths next to names
- `--show-used` to also list used assets and reference counts
- `--fail-on-unused` to return exit code 1 when unused assets are found
- `--strict-literals` to disable dynamic template matching (e.g. `chain_\(chain)`)
