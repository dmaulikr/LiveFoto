//
//  ShotViewController.swift
//  LiveFoto
//
//  Created by Leon.yan on 11/19/15.
//  Copyright © 2015 Tinycomic Inc. All rights reserved.
//

import UIKit
import GLKit
import AVFoundation
import QuartzCore
import CoreImage
import Photos

class ShotViewController: UIViewController, LFCameraDelegate {
    
    @IBOutlet weak var previewView : GLKView!
    @IBOutlet weak var heightConst : NSLayoutConstraint!
    
    var camera : LFCamera?
    var transformFilter : CIFilter?
    var cropFilter : CIFilter?
    var index : Double! = 0
    var crop : Bool! = false
    
    // writer
    var ciContext : CIContext?
    var colorSpace : CGColorSpace?
    var recordStart : Bool = false
    var recordStartTime : CMTime = kCMTimeInvalid
    var assetWriter : AVAssetWriter?
    var videoInput : AVAssetWriterInput?
    var pixelAdapter : AVAssetWriterInputPixelBufferAdaptor?
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        ciContext = CIContext(EAGLContext: LFEAGLContext.shareContext.glContext!,
            options: [kCIContextWorkingColorSpace : NSNull()])
        colorSpace = CGColorSpaceCreateDeviceRGB()
        previewView.context = LFEAGLContext.shareContext.glContext!
        previewView.enableSetNeedsDisplay = false
        
        camera = LFCamera(presentName: AVCaptureSessionPresetHigh)
        camera?.delegate = self
        camera?.initSession()
        
        transformFilter = CIFilter(name: "CIAffineTransform")
    }
    
    override func viewWillAppear(animated: Bool) {
        camera?.start()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    // MARK: LFCameraDelegate
    func capture(image: CIImage, time: CMTime) {
        transformFilter?.setValue(image, forKey: kCIInputImageKey)
        var transform = CGAffineTransformIdentity// CGAffineTransformTranslate(CGAffineTransformIdentity, -960, -540)
        transform = CGAffineTransformRotate(transform, CGFloat(M_PI_2 * 0.5))// / 1000.0 * self.index))
        
        transformFilter?.setValue(NSValue(CGAffineTransform : transform), forKey: kCIInputTransformKey)
        let ciimage : CIImage! = image.imageByApplyingTransform(transform)
        var extent : CGRect! = ciimage?.extent
//        extent.origin = CGPointZero
        
        cropFilter?.setValue(ciimage, forKey: kCIInputImageKey)
        extent.size = CGSizeMake(1080, 1080)
        extent.origin = CGPointMake(extent.origin.x  , extent.origin.y + (1920 - 1080) / 2.0)
        cropFilter?.setValue(CIVector(CGRect: extent), forKey: "inputRectangle")
        
        let cropedImage = cropFilter?.outputImage
        let cropedExtent = cropedImage?.extent as CGRect!
        
        EAGLContext.setCurrentContext(LFEAGLContext.shareContext.glContext)
        let width = CGFloat(previewView.drawableWidth)
        let height = CGFloat(previewView.drawableHeight)
        let bounds = CGRectMake(0, 0, width, height)
        
        if crop == true {
            camera?.ciContext?.drawImage(cropedImage!, inRect:bounds, fromRect: cropedExtent)
        } else {
            if recordStart == true {
                if CMTIME_IS_INVALID(recordStartTime) == true {
                    recordStartTime = time
                }
                
                var renderedOutputPixelBuffer : CVPixelBuffer? = nil
                CVPixelBufferPoolCreatePixelBuffer(nil, pixelAdapter!.pixelBufferPool!, &renderedOutputPixelBuffer)
                
                ciContext?.render(image,
                    toCVPixelBuffer: renderedOutputPixelBuffer!,
                    bounds: CGRectMake(0, 0, 1980, 1080),
                    colorSpace: colorSpace)
                
                let buf = CIImage(CVPixelBuffer: renderedOutputPixelBuffer!)

                previewView.bindDrawable()
                camera?.ciContext?.drawImage(buf, inRect:bounds, fromRect:buf.extent)
                previewView.display()
                
                if (videoInput?.readyForMoreMediaData == true) {
                    let presentationTime = CMTimeSubtract(time, recordStartTime)
                    let status = pixelAdapter?.appendPixelBuffer(renderedOutputPixelBuffer!, withPresentationTime: presentationTime)
                    if status == true {
                        NSLog("append pixel succ")
                    } else {
                        NSLog("error!")
                    }
                    
                    if CMTimeGetSeconds(presentationTime) > 1.0 {
                        recordStart = false
                        videoInput?.markAsFinished()
                        assetWriter?.finishWritingWithCompletionHandler({ () -> Void in
                            NSLog("OK!")
                        })
                    }
                }
                
            } else {
                previewView.bindDrawable()
                camera?.ciContext?.drawImage(ciimage!, inRect:bounds, fromRect: ciimage.extent)
                previewView.display()
            }
        }
        self.index = self.index + 1
    }
    
    // MARK : actions
    @IBAction func toggle(sender : UIButton!) {
        sender.selected = !sender.selected
        crop = sender.selected
        
        if crop == true {
            heightConst.constant = self.view.bounds.size.width
        } else {
            heightConst.constant = self.view.bounds.size.height
        }
        
        self.view.setNeedsUpdateConstraints()
        self.view.layoutIfNeeded()
    }
    
    @IBAction func snap(sender : UIButton!) {
        camera?.snapStill({ (result : Bool) -> Void in
            
        })
    }
    
    @IBAction func record(sender : UIButton!) {
        camera?.snapLivePhoto({ (result : Bool, uuid : String) -> Void in
            let videoURL = NSURL(fileURLWithPath: (NSTemporaryDirectory() + uuid + ".mov"))
            let imageURL = NSURL(fileURLWithPath: (NSTemporaryDirectory() + uuid + ".jpg"))
            
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                PHPhotoLibrary.sharedPhotoLibrary().performChanges({ () -> Void in
                    let request = PHAssetCreationRequest.creationRequestForAsset()
                    request.addResourceWithType(PHAssetResourceType(rawValue: 9)!, fileURL: videoURL, options: nil)
                    request.addResourceWithType(.Photo, fileURL: imageURL, options: nil)
                    }, completionHandler: { (result : Bool, error : NSError?) -> Void in
                    if result {
                        NSLog("save to camera roll as live phot")
                    } else {
                        NSLog("something wrong when saving : %@")
                    }
                })
            })
        })
        return
        let url = NSTemporaryDirectory().stringByAppendingString("out.mov")
        if NSFileManager.defaultManager().fileExistsAtPath(url) == true {
            do { try NSFileManager.defaultManager().removeItemAtPath(url) } catch {}
        }
        
        
        do {
            self.assetWriter = try AVAssetWriter(URL: NSURL(fileURLWithPath: url), fileType: AVFileTypeQuickTimeMovie)
        } catch (let error as NSError) {
            NSLog("%@", error)
        }
        
        precondition(self.assetWriter != nil)
        
        do {
            let outputSettings = [
                AVVideoCodecKey : AVVideoCodecH264,
                AVVideoWidthKey : NSNumber(int: 1980),
                AVVideoHeightKey: NSNumber(int: 1080)
            ]
            self.videoInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: outputSettings)
            self.videoInput!.transform = CGAffineTransformMakeRotation(CGFloat(M_PI_2))
            
            /*
            NSDictionary *pixelBufferAttributes =
            @{
            (id) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
            (id) kCVPixelBufferWidthKey : @(self.currentVideoDimensions.width),
            (id) kCVPixelBufferHeightKey : @(self.currentVideoDimensions.height),
            (id) kCVPixelBufferOpenGLESCompatibilityKey : @(YES),
            };
*/
            let pixelAttributes =
            [
                kCVPixelBufferPixelFormatTypeKey as String : NSNumber(unsignedInt: kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String : NSNumber(double: 1920),
                kCVPixelBufferHeightKey as String : NSNumber(double: 1080),
                kCVPixelBufferOpenGLESCompatibilityKey as String : NSNumber(bool: true),
            ]
            self.pixelAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.videoInput!, sourcePixelBufferAttributes: pixelAttributes)
            self.assetWriter!.addInput(self.videoInput!)
            
            self.assetWriter!.startWriting()
            self.assetWriter!.startSessionAtSourceTime(kCMTimeZero)
            self.recordStart = true
        } catch ( let error as NSError){
           NSLog("%@", error)
        }
    }
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
