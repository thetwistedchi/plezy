use std::ffi::{CStr, CString};
use std::time::Instant;
use plezy_adblock::*;

fn main() {
    let lists: Vec<String> = std::env::args().skip(2).collect();
    let resources = std::env::args().nth(1).unwrap();
    let cfg = serde_json::json!({
        "lists": lists.iter().map(|p| serde_json::json!({"path": p, "trusted": true})).collect::<Vec<_>>(),
        "userFilters": "||example-ad-host.test^\n##.banner-ad\n###sidebar-ad\n",
        "resources": resources,
        "cache": "/tmp/ab.dat",
        "cacheKey": "k2",
    });
    let c = CString::new(cfg.to_string()).unwrap();
    let t = Instant::now();
    let e = plezy_adblock_load(c.as_ptr());
    println!("load {:?} null={}", t.elapsed(), e.is_null());
    let t = Instant::now();
    let e2 = plezy_adblock_load(c.as_ptr());
    println!("cached load {:?} null={}", t.elapsed(), e2.is_null());
    let checks = [
        ("https://example-ad-host.test/x.js", "https://news.example.com/", "script"),
        ("https://www.googletagmanager.com/gtm.js?id=x", "https://news.example.com/", "script"),
        ("https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js", "https://news.example.com/", "script"),
        ("https://securepubads.g.doubleclick.net/tag/js/gpt.js", "https://news.example.com/", "script"),
        ("https://news.example.com/app.js", "https://news.example.com/", "script"),
        ("https://www.google-analytics.com/analytics.js", "https://news.example.com/", "script"),
        ("https://willalland.info/", "https://willalland.info/", "document"),
        ("https://doathair.com/page", "https://doathair.com/page", "main_frame"),
        ("https://doathair.com/x.js", "https://news.example.com/", "script"),
    ];
    for (u, s, k) in checks {
        let mut r: *mut std::ffi::c_char = std::ptr::null_mut();
        let cu = CString::new(u).unwrap(); let cs = CString::new(s).unwrap(); let ck = CString::new(k).unwrap();
        let t = Instant::now();
        let res = plezy_adblock_check(e2, cu.as_ptr(), cs.as_ptr(), ck.as_ptr(), &mut r);
        let el = t.elapsed();
        let red = if r.is_null() { String::new() } else { let x = unsafe{CStr::from_ptr(r)}.to_string_lossy()[..40.min(unsafe{CStr::from_ptr(r)}.to_bytes().len())].to_string(); plezy_adblock_free_string(r); x };
        println!("{res} {el:?} {u} {red}");
    }
    for page in ["https://www.youtube.com/watch?v=x", "https://www.spiegel.de/", "https://example.com/"] {
        let cp = CString::new(page).unwrap();
        let j = plezy_adblock_url_cosmetic(e2, cp.as_ptr());
        let s = unsafe{CStr::from_ptr(j)}.to_string_lossy().to_string();
        let v: serde_json::Value = serde_json::from_str(&s).unwrap();
        println!("{page}: hide {} script {} bytes generichide {}", v["hide"].as_array().unwrap().len(), v["script"].as_str().unwrap().len(), v["generichide"]);
        plezy_adblock_free_string(j);
    }
    let q = CString::new(r#"{"c":["ad","ads","adsbygoogle","banner-ad"],"i":["ad","sidebar-ad"],"e":[]}"#).unwrap();
    let j = plezy_adblock_hidden_selectors(e2, q.as_ptr());
    println!("generic: {}", unsafe{CStr::from_ptr(j)}.to_string_lossy());
    let q2 = CString::new(r#"{"c":["banner-ad","x"],"i":["sidebar-ad"]}"#).unwrap();
    let ex = CString::new("[]").unwrap();
    let g = plezy_adblock_generic_script(e2, q2.as_ptr(), ex.as_ptr());
    if !g.is_null() { let t = unsafe{CStr::from_ptr(g)}.to_string_lossy().to_string(); std::fs::write("/tmp/generic.js", &t).unwrap(); println!("generic script: {t}"); plezy_adblock_free_string(g); }
    plezy_adblock_free_string(j);
    for page in ["https://www.youtube.com/watch?v=x", "https://example.com/"] {
        let cp = CString::new(page).unwrap();
        let mut ex: *mut std::ffi::c_char = std::ptr::null_mut();
        let mut gh = 0;
        let js = plezy_adblock_page_script(e2, cp.as_ptr(), &mut ex, &mut gh);
        if !js.is_null() {
            let text = unsafe{CStr::from_ptr(js)}.to_string_lossy().to_string();
            std::fs::write(format!("/tmp/page-{}.js", page.len()), &text).unwrap();
            println!("{page}: script {} bytes, exceptions {}", text.len(), unsafe{CStr::from_ptr(ex)}.to_string_lossy().len());
            plezy_adblock_free_string(js);
        }
        plezy_adblock_free_string(ex);
    }
    plezy_adblock_free(e); plezy_adblock_free(e2);
}
