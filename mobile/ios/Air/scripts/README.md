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
