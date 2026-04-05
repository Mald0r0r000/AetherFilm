//Ghidra Script: Analyze OFX Metal Plugin
//@category Analysis

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolTable;
import ghidra.program.model.address.Address;

public class AnalyzeOFXMetal extends GhidraScript {
    
    String[] searchTerms = {
        "processImagesMetal",
        "processImagesCUDA",
        "processImagesOpenCL",
        "multiThreadProcessImages",
        "process",
        "setGPURenderArgs",
        "setSupportsMetalRender",
        "_pMetalCmdQ",
        "_pCudaStream",
        "_isEnabledMetalRender",
        "getPixelData",
        "MetalCommandQueue",
        "MTLDevice",
        "MTLTexture"
    };
    
    @Override
    public void run() throws Exception {
        println("============================================================");
        println("OFX Metal Plugin Analysis");
        println("============================================================");
        
        // Search functions by name
        println("\n--- FUNCTIONS FOUND ---\n");
        
        for (String term : searchTerms) {
            java.util.Set<Function> funcs = getGlobalFunctions(term);
            if (funcs != null && funcs.size() > 0) {
                for (Function f : funcs) {
                    println("[" + term + "]:");
                    println("  Address: " + f.getEntryPoint());
                    println("  Signature: " + f.getSignature());
                    println("");
                }
            }
        }
        
        // Search symbols
        println("\n--- SYMBOLS ---\n");
        SymbolTable symbolTable = currentProgram.getSymbolTable();
        
        for (String term : searchTerms) {
            for (Symbol sym : symbolTable.getSymbols(term)) {
                println("Symbol: " + sym.getName() + " at " + sym.getAddress());
            }
        }
        
        // Search strings in memory
        println("\n--- METAL STRINGS ---\n");
        
        String[] metalStrings = {"Metal", "metal", "METAL", "MTLDevice", "metallib"};
        
        for (String s : metalStrings) {
            Address addr = findBytes(currentProgram.getMemory().getMinAddress(), s.getBytes(), null);
            if (addr != null) {
                println("String '" + s + "' found at: " + addr);
            }
        }
        
        println("\n============================================================");
        println("Analysis Complete");
        println("============================================================");
    }
}
