#![feature(unboxed_closures)]
#![feature(allocator_api)]
use std::num::NonZeroU32;
use winit::event::{ElementState, Event, KeyEvent, WindowEvent};
use winit::event_loop::{ControlFlow, EventLoop, EventLoopBuilder};
use winit::keyboard::{Key, NamedKey};
use color_eyre::{eyre::eyre,Result};
use winit::window::Window;
use winit::event_loop::ActiveEventLoop;
use std::rc::Rc;

// NOTE README TODO ..... 
// NOTE README TODO .....  The error handling in the window drawer code is sort of bad, this is due
// to the library used having a variety of issues with the api it exposes. Im aware though I just
// quickly needed a surface to draw on
// NOTE README TODO ..... 

include!("utils/winit_app.rs");


#[no_mangle]
pub extern "C" fn draw_png(xres: c_uint, yres: c_uint, buf: *const c_float) -> c_uint {
    if let Err(e) = try_draw_png( xres, yres, buf) {
        println!("error drawing window: {e}");
        1
    } else {
        0
    }
}

fn try_draw_png(xres: c_uint, yres: c_uint, buf: *const c_float) -> Result<()> {
    use png::Encoder;
    use std::path::Path;
    use std::fs::File;
    use std::io::BufWriter;

    println!("t");
    let pixcount: usize  = (xres * yres).try_into()?;
    let rgbcount = pixcount * 3;

    let aplbuf: &[f32] = unsafe { std::slice::from_raw_parts(buf, rgbcount) };

    let ma = (std::u8::MAX).into();
    let mi = (std::u8::MIN).into();
    let rgbbuf = aplbuf.into_iter().map(|c: &f32| -> u8 {
            let c = c * 255.0;
            if &c > &ma  {
                0xff
            } else if &c <= &mi  {
                0x0
            } else {
                let c: u32 = c as _;
                println!("{c}");
                c.try_into().unwrap() 
            }
    }).collect::<Vec<u8>>();



    let path = Path::new(r"rendering.png");
    let file = File::create(path)?;
    let w = &mut BufWriter::new(file);
    let mut enc = Encoder::new(w,xres, yres);
    enc.set_color(png::ColorType::Rgb);
    enc.set_depth(png::BitDepth::Eight);
    let mut writer = enc.write_header()?;
    writer.write_image_data(&rgbbuf).map_err(|e| eyre!("{e}"))
}


fn redraw(buffer: &mut [u32], width: usize, height: usize, flag: bool) {
    for y in 0..height {
        for x in 0..width {
            let value = if flag && x >= 100 && x < width - 100 && y >= 100 && y < height - 100 {
                0x00ffffff
            } else {
                let red = (x & 0xff) ^ (y & 0xff);
                let green = (x & 0x7f) ^ (y & 0x7f);
                let blue = (x & 0x3f) ^ (y & 0x3f);
                (blue | (green << 8) | (red << 16)) as u32
            };
            buffer[y * width + x] = value;
        }
    }
}

use std::ffi::{c_void, c_uint, c_float ,c_double};
use std::ptr;

// 'init_drawer'⎕NA'P /home/flandre/apl-raymarcher/target/debug/libapl_window_draw_helper.so|init_drawer'
#[no_mangle]
pub extern "C" fn init_window_drawer() -> *const c_void {

    match try_init_drawer() {
        Ok(v) => {
            v
        },
        Err(e) => {
            println!("error drawing window: {:#?}",e);
            ptr::null_mut()
        },
    }
}


struct Shared<D,W> {
    surface: softbuffer::Surface<D,W>,
    dimensions: (usize,usize),
}

fn try_init_drawer() -> Result<*const c_void> {
    use winit::platform::wayland::EventLoopBuilderExtWayland;
    println!("eee");
    let event_loop = EventLoopBuilder::new()
        .with_any_thread(true)
        .build()?;
    
    let shared = std::sync::Arc::new(std::sync::Mutex::new(None));

    let app = winit_app::WinitAppBuilder::with_init({ let shared = shared.clone(); move |elwt| {
        let window = winit_app::make_window(elwt, |w| {
            w.with_title("Press space to show/hide a rectangle")
        });

        let context = softbuffer::Context::new(window.clone()).expect("couldn crate softbuffer context");
        let surface = softbuffer::Surface::new(&context, window.clone()).expect("couldn't create surface");
        let mut sh = shared.lock().expect("cloudn't get mutex lock");
        *sh = Some(Shared {
            surface,
            dimensions: (0,0),
        });

        let flag = false;

        (window,shared.clone(),flag)
    }})
    .with_event_handler(|state, event, elwt: &ActiveEventLoop| {
        let (window,shared,flag) = state;

        elwt.set_control_flow(ControlFlow::Wait);

        if let Err(e) = (|| -> Result<()> { match event {
            Event::WindowEvent {
                window_id,
                event: WindowEvent::RedrawRequested,
            } => {
                if window_id == window.id() {
                    // Grab the window's client area dimensions
                    if let (Some(width), Some(height)) = {
                        let size = window.inner_size();
                        (NonZeroU32::new(size.width), NonZeroU32::new(size.height))
                    } {
                        let shared = shared.lock();

                        let mut shared = shared.expect("couldn't reclaim mutex lock");
                        let shared = shared.as_mut().ok_or(eyre!("shared drawer uninitialized"))?;

                        let mut surface = &mut shared.surface;
                        let mut dimensions = &mut shared.dimensions;
                        surface.resize(width, height)
                            .map_err(|e| eyre!("{e}"))?;

                        *dimensions = (width
                                       .get()
                                       .try_into()
                                       .map_err(|e| eyre!("xres conversion error {e}"))?,
                                       height
                                       .get()
                                       .try_into()
                                       .map_err(|e| eyre!("yres conversion error {e}"))?);

                        // Draw something in the window
                        let mut buffer = surface.buffer_mut()
                            .map_err(|e| eyre!("{e}"))?;



                        redraw(
                            &mut buffer,
                            width.get() as usize,
                            height.get() as usize,
                            *flag,
                        );
                        buffer.present()
                            .map_err(|e| eyre!("{e}"))?;
                    }
                }
                Ok(())
            },

            Event::WindowEvent {
                event:
                    WindowEvent::CloseRequested
                    | WindowEvent::KeyboardInput {
                        event:
                            KeyEvent {
                                logical_key: Key::Named(NamedKey::Escape),
                                ..
                            },
                        ..
                    },
                window_id,
            } => {
                if window_id == window.id() {
                    println!("closing");
                    elwt.exit();
                }
                Ok(())
            },
            _ => { Ok(()) }
        }})() {
            println!("ERROR in eventloop {e}");
        }
    });

    let s = shared.clone();
    // dirty hack as the library used Rc<> which
    // isn't thread safe while the actual context seems to be
    // Wouldn't use in production but i mean after all
    // this is just tool for a fun project
    unsafe impl<D,W> Send for Shared<D,W> {};
    struct A<T>(T);
    struct B<T>(T);
    struct C<T>(T);

    unsafe impl<T> Send for C<T> {}
    unsafe impl<T> Send for B<T> {}
    unsafe impl<T> Send for A<T> {}
    let a = A(event_loop);
    let b = B(app);

    let c = C((|a: A<_>,b: B<_>| {
        winit_app::run_app(a.0, b.0) 
    }));

    std::thread::spawn(move || c.0(a,b) );
    // dirty trick to ensure the thread were spawning
    // is properly initialized. In production software there wouldn't be the
    // need to do this as I wouldn't use a library that relied on Rc<> in a multithreaded
    // context ... 
    std::thread::sleep_ms(4000);

    Ok(&s as *const _ as *const c_void)
}

use std::sync::{Mutex,Arc};
use std::alloc::Global;

// 'get_res'⎕NA'U4 /home/flandre/apl-raymarcher/target/debug/libapl_window_draw_helper.so|get_res P >U4[2]'
// TODO wee need a sync primitive to ensure the window isn't resized 
// while we draw making the buffer invalid
// return 2 uint array [x y] ptr
#[no_mangle]
pub extern "C" fn get_res_window(p: *const c_void,out: *mut c_uint) -> c_uint { // APL u4
    // build in delay to give me time to set the window size 
    std::thread::sleep_ms(4000);
    let c = (|| -> Result<_> {
        let s: *const Arc<Mutex<Option<Shared<Rc<Window, Global>, Rc<Window, Global>>>>, Global>  = p as *const _;
        let s = unsafe { s.read() };
        let dimensions = s.lock()
            .map_err(|e| eyre!("cloudn't acquire mutex lock {e}"))?
            .as_ref()
            .ok_or(eyre!("dimension storage uninitialized"))?
            .dimensions;
        Ok((dimensions.0.try_into().map_err(|e| eyre!("xres conversion error {e}"))?,
        dimensions.1.try_into().map_err(|e| eyre!("yres conversion error {e}"))?))
    })();
    match c {
        Ok(c) => {
            let out  = unsafe { std::slice::from_raw_parts_mut(out, 2) };
            out[0] = c.0;
            out[1] = c.1;
            0
        },
        Err(e) => {
            println!("{e}");
            1
        }
    }
}


// TODO fetch the current res and compare it to what was supplied so 
// copy from slice as we can't guarantee ownership over the lock
// we can't guarantee that the eventloop has resized the window
// while the apl side is doing the calculations
#[no_mangle]
pub extern "C" fn draw_window(p: *const c_void, xres: c_uint, yres: c_uint, buf: *const c_float) -> c_uint {
    if let Err(e) = try_draw_window(p, xres, yres, buf) {
        println!("error drawing window: {e}");
        1
    } else {
        0
    }
}
fn try_draw_window(p: *const c_void, xres: c_uint, yres: c_uint, buf: *const c_float) -> Result<()> {
    let s: *const Arc<Mutex<Option<Shared<Rc<Window, Global>, Rc<Window, Global>>>>, Global>  = p as *const _;
    let s = unsafe { s.read() };

    let mut b = s.lock().map_err(|e| eyre!("{e}"))?;
    let mut _drawbuf = b.as_mut()
        .ok_or(eyre!("surface context uninitialized"))?
        .surface.buffer_mut().map_err(|e| eyre!("{e}"))?;
    let drawbuf: &mut [u32] = &mut _drawbuf;

    let pixcount = (xres * yres).try_into()?;
    let rgbacount = pixcount * 4;

    let aplbuf  = unsafe { std::slice::from_raw_parts(buf, rgbacount) };

    println!("pc {} @ {} x {} ", rgbacount, xres, yres);
    let mut rgbabuf: Vec<u32> = Vec::with_capacity(pixcount);

    let mut i = 0;
    while i < rgbacount {
        let t = |mut c: f32| -> u32{
            c *= 255.0;
            if c > 255.0 {
                0xff
            } else if c <= 0.0 {
                0x0
            } else {
                c as _
            }
        };

        let (red,green,blue) = (
            t(aplbuf[i]),
            t(aplbuf[i+1]),
            t(aplbuf[i+2])
        );
        let col = (blue | (green << 8) | (red << 16)) as u32;


        rgbabuf.push ( col );
        i += 4;
    }
    
    // im aware i could directly write into the buffer but I might
    // want to do some post processing 
    drawbuf.copy_from_slice(&rgbabuf);
    _drawbuf.present().map_err(|e| eyre!("{e}"))
}
