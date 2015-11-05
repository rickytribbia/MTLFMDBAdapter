//
//  MTLFMDBAdapter.h
//  Mantle
//
//  Created by Valerio Santinelli on 16/07/14.
//  Copyright (c) 2014 Valerio Santinelli. All rights reserved.
//

#import <Foundation/Foundation.h>

#define QUERY_PARAMS_KEY_QUERY  @"mtlfmdbadapter.queryparams.key.query"
#define QUERY_PARAMS_KEY_ARGS   @"mtlfmdbadapter.queryparams.key.args"

@class MTLModel;
@class FMResultSet;
@class FMDatabase;
@protocol MTLFMDBSerializing;

static const void *MTLFMDBRowIdKey = &MTLFMDBRowIdKey;

@interface MTLModel (MTLFMDBExtensions)

@property (nonatomic) NSInteger mtlfmdb_rowid;

/** 
 Recupera tutti gli oggetti dal DB passato come parametro e li restituisce in modo asincrono nel blocco di completamento insieme al db stesso per eventuali operazioni da eseguire nello stesso thread sullo stesso DB
 */
+ (void) allObjectsFromDB:(FMDatabase *)db withCompletion:(void(^)(NSArray *objects, FMDatabase *db))completionBlock;

/**
 @result Statement per salvare l'oggetto sul DB
 */
- (NSString*) saveStatement;

/**
 @result Statement per eliminare l'oggetto dal DB
 */
- (NSString*) deleteStatement;

/**
 @result parametri per eliminare l'oggetto dal DB
 */
- (NSDictionary*) deleteParams;

@end

/**
 *  A MTLModel object that supports being parsed from and serialized to FMDB.
 */
@protocol MTLFMDBSerializing

@required

/**
 Specify how to map property keys to different columns in FMDB.
 
 Subclasses overriding this method should combine their values with those of
 `super`.
 
 Any property keys not present in the dictionary are assumed to match the column
 name that should be used. 
 Any keys associated with NSNull will not participate
 in serialization.

 @return a dictionary mapping property keys to FMDB columns (as strings) or 
 NSNull values.
 */
+ (NSDictionary *)FMDBColumnsByPropertyKey;

/**
 Specify the table name for this object.
 
 @return an NSString with the name of the table.
 */
+ (NSString *)FMDBTableName;

/*
 Methods for load operation.
 In this method you need to map all field to result set
 */
- (void) loadFromResultSet:(FMResultSet*)resultSet;

/**
 Methods for save operation.
 In this method you need to map all field to result set
 */
- (void) saveAsync:(BOOL)async
    withCompletion:(void(^)(BOOL result))completionBlock;


- (NSDictionary*) saveParams;

@optional

/**
 Specify the `NSValueTransformer` that should be used to transform values
 fetched from FMDB.
 
 @param key The key corresponding to the column in FMDB
 
 @return the `NSValueTransformer` that should be used
 */
- (NSValueTransformer *)FMDBTransformerForKey:(NSString *)key;

/**
 Metodo opzionale per restituire il tipo particolare legato ad una proprietà specifica
 */
+ (NSDictionary *)FMDBColumnsTypeByPropertyKey;

@end

/**
 The domain for errors originating from MTLFMDBAdapter.
 */
extern NSString * const MTLFMDBAdapterErrorDomain;

/**
 The provided FMDBDictionary is not valid.
 */
extern const NSInteger MTLFMDBAdapterErrorInvalidFMResultSet;

/**
 The model's implementation of +FMDBColumnsByPropertyKey included a key which
 does not actually exist in +propertyKeys.
 */
extern const NSInteger MTLFMDBAdapterErrorInvalidFMResultSetMapping;

/**
 Converts a MTLModel object from and FMResultSet and to a SQL query that can
 be fed to FMDB
 */
@interface MTLFMDBAdapter : NSObject

/**
 The model object that the receiver was initialized with, or that the receiver
 parsed from an FMResultSet.
 */
@property (nonatomic, strong, readonly) MTLModel<MTLFMDBSerializing> *model;

/**
 Attempts to parse an FMResultSet into a model object.
 
 @param modelClass The MTLModel subclass to attempt to parse from the FMResultSet.
 @param resultSet  An FMResultSet with the data to be converted to a MTLModel.
                   If this argument is nil, the method returns nil.
 @param error      If not NULL, this may be set to an error that occurs during
                   parsing or initializing an instance of `modelClass`
 
 @return an instance of `modelClass` upon success, or nil if a parsing error
 occurred.
 */
+ (id)modelOfClass:(Class)modelClass fromFMResultSet:(FMResultSet *)resultSet error:(NSError **)error;

/**
 Initializes the receiver by attempting to parse an FMResultSet into a model object.
 
 @param resultSet  The FMResultSet representing the data to be converted to a MTLModel. If this argument is nil, the method returns nil.
 @param modelClass The MTLModel subclass to attempt to parse from the FMResultSet.
 @param error      If not NULL, this may be set to an error that occurs during parsing or initializing an instance of `modelClass`
 
 @return an instance of `modelClass` upon success, or nil if a parsing error occurred.
 */
- (id)initWithFMResultSet:(FMResultSet *)resultSet modelClass:(Class)modelClass error:(NSError **)error;

// Serializes the receiver's `model` into an NSDictionary.
//
// Returns a JSON dictionary, or nil if a serialization error occurred.
- (NSDictionary *)FMDBDictionary;

// Looks up the FMDB column in the model's +propertyKeys.
//
// Subclasses may override this method to customize the adapter's seralizing
// behavior. You should not call this method directly.
//
// key - The property key to retrieve the corresponding column for. This
//       argument must not be nil.
//
// Returns a column to use, or nil to omit the property.
- (NSString *)FMDBColumnForPropertyKey:(NSString *)key;

/**
 Looks up the column names of the properties described in FMDBColumnsByPropertyKey and returns them as an NSArray
 
 @param modelClass the MTLModel class whose columns names should be returned
 
 @return an NSArray of columns names of the properties in the same order as described by FMDBColumnsByPropertyKey
 */
+ (NSArray*) columnsNamesForModelClass:(Class)modelClass;

/**
 Looks up the column names of the properties described in FMDBColumnsByPropertyKey and returns them as an NSDictionary
 
 @param modelClass the MTLModel class whose columns names should be returned
 
 @return an NSDictionary with keys as property name and value of effective columns names of the properties
 */
+ (NSDictionary*) columnsNamesDictionaryForModelClass:(Class)modelClass;

/**
 Looks up the values of the primary keys.
 
 @param model the MTLModel object whose primary keys values should be returned.
 
 @return an NSArray of values of the primary keys of `model`
 */
+ (NSArray *)primaryKeysValues:(MTLModel<MTLFMDBSerializing> *)model;


/**
 The SQL CREATE TABLE statement for the object passed in `model`
 
 @param model the MTLModel object we want to serialize to FMDB
 
 @return an NSString with the CREATE TABLE statement to use with FMDB.
 */
+ (NSString *)createStatementForModel:(Class)modelClass;

/**
 The SQL DELETE TABLE statement for the object passed in `model`
 
 @param model the MTLModel object we want to serialize to FMDB
 
 @return an NSString with the DELETE TABLE statement to use with FMDB.
 */
+ (NSString *)deleteStatementForModelClass:(Class)modelClass;


/**
 The SQL INSERT statement for the object passed in `model`
 
 @param model the MTLModel object we want to serialize to FMDB
 
 @return an NSString with the INSERT statement to use with FMDB.
 */
+ (NSString *)insertStatementForModel:(MTLModel<MTLFMDBSerializing> *)model;

/**
 The SQL UPDATE statement for the object passed in `model`
 
 @param model the MTLModel object we want to serialize to FMDB
 
 @return an NSString with the INSERT statement to use with FMDB.
 */
+ (NSString *)updateStatementForModel:(MTLModel<MTLFMDBSerializing> *)model;

/**
 The SQL DELETE statement for the object passed in `model`
 
 @param model the MTLModel object we want to serialize to FMDB
 
 @return an NSString with the INSERT statement to use with FMDB.
 */
+ (NSString *)deleteStatementForModel:(MTLModel<MTLFMDBSerializing> *)model;

/**
 The WHERE statement used for UPDATE and DELETE operations.
 
 @param model the MTLModel object we want to serialize to FMDB
 
 @return an NSString with the WHERE statement of the query.
 */
+ (NSString *)whereStatementForModel:(MTLModel<MTLFMDBSerializing> *)model;
@end
