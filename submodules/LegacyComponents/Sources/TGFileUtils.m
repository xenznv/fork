#import <LegacyComponents/TGFileUtils.h>

#import <MobileCoreServices/MobileCoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

NSString *TGMimeTypeForFileExtension(NSString *fileExtension)
{
    return [UTType typeWithFilenameExtension:fileExtension].preferredMIMEType;
}

NSString *TGMimeTypeForFileUTI(NSString *fileUTI)
{
    NSString *mimeType = [UTType typeWithIdentifier:fileUTI].preferredMIMEType;
    if (mimeType == nil)
        mimeType = @"application/octet-stream";
    return mimeType;
}

NSString *TGTemporaryFileName(NSString *fileExtension)
{
    if (fileExtension == nil)
        fileExtension = @"bin";
    
    int64_t randomId = 0;
    arc4random_buf(&randomId, sizeof(randomId));
    
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSString alloc] initWithFormat:@"%" PRIx64 ".%@", randomId, fileExtension]];
}
