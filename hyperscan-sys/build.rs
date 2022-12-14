use std::env;
use std::path;

#[cfg(feature = "hyperscan")]
const SOURCE: &str = "hyperscan";

#[cfg(feature = "vectorscan")]
const SOURCE: &str = "vectorscan";

fn main() {
    let out_path = path::PathBuf::from(env::var("OUT_DIR").unwrap());
    #[allow(unused_mut)]
    let mut config = bindgen::Builder::default()
        .allowlist_function("hs_.*")
        .allowlist_type("hs_.*")
        .allowlist_var("HS_.*")
        .header("wrapper.h");

    #[cfg(any(feature = "hyperscan", feature = "vectorscan"))]
    {
        let src_dir = path::Path::new(env!("CARGO_MANIFEST_DIR")).join(SOURCE);
        src_dir
            .try_exists()
            .expect("Hyperscan source directory doesn't exist");
        let include_dir = out_path
            .join("include")
            .into_os_string()
            .into_string()
            .unwrap();
        let out = String::from_utf8(
            std::process::Command::new("c++")
                .args(["-v"])
                .output()
                .expect("Cannot find C++ compiler")
                .stderr,
        )
        .unwrap();

        if out.contains("gcc") {
            println!("cargo:rustc-link-lib=stdc++");
        } else if out.contains("clang") {
            println!("cargo:rustc-link-lib=c++");
        } else {
            panic!("No compatible compiler found. Either clang or gcc is needed.");
        }

        let arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap();
        let vendor = env::var("CARGO_CFG_TARGET_VENDOR").unwrap();
        // TODO: this could work on intel apple targets if build scripts wouldn't be that fragile
        let toggle = if arch == "x86_64" && vendor != "apple" {
            "ON"
        } else {
            "OFF"
        };

        let dst = cmake::Config::new(&src_dir)
            .profile("release")
            .define("CMAKE_INSTALL_INCLUDEDIR", &include_dir)
            .define("FAT_RUNTIME", toggle)
            .define("BUILD_AVX512", toggle)
            .build();

        println!("cargo:rerun-if-changed={}", file!());
        println!("cargo:rerun-if-changed={}", src_dir.to_str().unwrap());
        println!("cargo:rustc-link-lib=static=hs");
        println!(
            "cargo:rustc-link-search={}",
            dst.join("lib").to_str().unwrap()
        );
        println!(
            "cargo:rustc-link-search={}",
            dst.join("lib64").to_str().unwrap()
        );

        config = config.clang_arg(format!("-I{}", &include_dir));
    }
    #[cfg(not(any(feature = "hyperscan", feature = "vectorscan")))]
    {
        println!("cargo:rustc-link-lib=hs");
    }

    config
        .generate()
        .expect("Unable to generate bindings")
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}
