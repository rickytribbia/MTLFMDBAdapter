//
//  MTLFMDBAdapter.m
//  TiVoto
//
//  Created by Valerio Santinelli on 16/07/14.
//  Copyright (c) 2014 Altralogica s.r.l. All rights reserved.
//

#import <objc/runtime.h>
#import <Mantle/Mantle.h>
#import <Mantle/MTLEXTRuntimeExtensions.h>
#import <Mantle/MTLEXTScope.h>
#import <Mantle/MTLReflection.h>
#import <FMDB/FMDB.h>
#import "MTLFMDBAdapter.h"

NSString * const MTLFMDBAdapterErrorDomain = @"MTLFMDBAdapterErrorDomain";
const NSInteger MTLFMDBAdapterErrorInvalidFMResultSet = 2;
const NSInteger MTLFMDBAdapterErrorInvalidFMResultSetMapping = 3;

// An exception was thrown and caught.
const NSInteger MTLFMDBAdapterErrorExceptionThrown = 1;

// Associated with the NSException that was caught.
static NSString * const MTLFMDBAdapterThrownExceptionErrorKey = @"MTLFMDBAdapterThrownException";


@implementation MTLModel (MTLFMDBExtensions)

- (NSInteger) mtlfmdb_rowid
{
    return [objc_getAssociatedObject(self, MTLFMDBRowIdKey) integerValue];
}

- (void) setMtlfmdb_rowid:(NSInteger)mtlfmdb_rowid
{
    objc_setAssociatedObject(self, MTLFMDBRowIdKey, @(mtlfmdb_rowid), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void) allObjectsFromDB:(FMDatabase *)db withCompletion:(void(^)(NSArray *objects, FMDatabase *db))completionBlock
{
    if([self conformsToProtocol:@protocol(MTLFMDBSerializing)]){
        MTLModel<MTLFMDBSerializing> *model = (MTLModel<MTLFMDBSerializing> *)self;
        FMResultSet *resultSet = [db executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@",[model.class FMDBTableName]]];
        
        if (resultSet != nil) {
            NSMutableArray *result = [[NSMutableArray alloc] init];
            while ([resultSet next]) {
                MTLModel<MTLFMDBSerializing> *object = [[self alloc] init];
                [object loadFromResultSet:resultSet];
            }
            [resultSet close];
            completionBlock([result copy],db);
        }else{
            completionBlock(nil,db);
        }
    }else{
        completionBlock(nil,db);
    }
}

- (NSString *)saveStatement
{
    return (self.mtlfmdb_rowid > 0) ? [MTLFMDBAdapter updateStatementForModel:(MTLModel<MTLFMDBSerializing>*)self] : [MTLFMDBAdapter insertStatementForModel:(MTLModel<MTLFMDBSerializing>*)self];
}

- (NSString *)deleteStatement
{
    MTLModel<MTLFMDBSerializing> *object = (MTLModel<MTLFMDBSerializing> *)self;
    return [NSString stringWithFormat:@"delete from %@ where mtlfmdb_rowid = :id",[object.class FMDBTableName]];
}

- (NSDictionary *)deleteParams
{
    return @{@"id" : @(self.mtlfmdb_rowid)};
}

@end

@interface MTLFMDBAdapter ()

// The MTLModel subclass being parsed, or the class of `model` if parsing has
// completed.
@property (nonatomic, strong, readonly) Class modelClass;

@property (nonatomic, copy, readonly) NSDictionary *FMDBColumnsByPropertyKey;

@end

@implementation MTLFMDBAdapter

#pragma mark Convenience methods

+ (id)modelOfClass:(Class)modelClass fromFMResultSet:(FMResultSet *)resultSet error:(NSError **)error {
	MTLFMDBAdapter *adapter = [[self alloc] initWithFMResultSet:resultSet modelClass:modelClass error:error];
	return adapter.model;
}

- (id)init {
	NSAssert(NO, @"%@ must be initialized with a FMResultSet or model object", self.class);
	return nil;
}

- (id)initWithFMResultSet:(FMResultSet *)resultSet modelClass:(Class)modelClass error:(NSError **)error
{
	NSParameterAssert(modelClass != nil);
	NSParameterAssert([modelClass isSubclassOfClass:MTLModel.class]);
	NSParameterAssert([modelClass conformsToProtocol:@protocol(MTLFMDBSerializing)]);
    
	if (resultSet == nil || ![resultSet isKindOfClass:FMResultSet.class]) {
		if (error != NULL) {
			NSDictionary *userInfo = @{
                                       NSLocalizedDescriptionKey: NSLocalizedString(@"Missing FMResultSet", @""),
                                       NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:NSLocalizedString(@"%@ could not be created because an invalid result set was provided: %@", @""), NSStringFromClass(modelClass), resultSet.class],
                                       };
			*error = [NSError errorWithDomain:MTLJSONAdapterErrorDomain code:MTLJSONAdapterErrorInvalidJSONDictionary userInfo:userInfo];
		}
		return nil;
	}
    
	self = [super init];
	if (self == nil) return nil;
    
	_modelClass = modelClass;
	_FMDBColumnsByPropertyKey = [[modelClass FMDBColumnsByPropertyKey] copy];
    
	NSMutableDictionary *dictionaryValue = [[NSMutableDictionary alloc] initWithCapacity:self.FMDBDictionary.count];
    
	NSSet *propertyKeys = [self.modelClass propertyKeys];
    NSArray *Keys = [[propertyKeys allObjects] sortedArrayUsingSelector:@selector(compare:)];
    
	for (NSString *columnName in self.FMDBColumnsByPropertyKey) {
		if ([Keys containsObject:columnName]) continue;
        
		if (error != NULL) {
			NSDictionary *userInfo = @{
                                       NSLocalizedDescriptionKey: NSLocalizedString(@"Invalid FMDB mapping", nil),
                                       NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:NSLocalizedString(@"%1$@ could not be parsed because its FMDB mapping contains illegal property keys.", nil), modelClass]
                                       };
            
			*error = [NSError errorWithDomain:MTLFMDBAdapterErrorDomain code:MTLFMDBAdapterErrorInvalidFMResultSetMapping userInfo:userInfo];
		}
        
		return nil;
	}
    
	for (NSString *propertyKey in Keys) {
		NSString *columnName = [self FMDBColumnForPropertyKey:propertyKey];
		if (columnName == nil) continue;
        
        objc_property_t theProperty = class_getProperty(modelClass, [propertyKey UTF8String]);
        mtl_propertyAttributes *attributes = mtl_copyPropertyAttributes(theProperty);
		id value;
		@try {
            if ([attributes->objectClass isSubclassOfClass:[NSNumber class]]) {
                NSString *stringForColumn = [resultSet stringForColumn:columnName];
                if(stringForColumn)
                    value = [NSNumber numberWithDouble:[stringForColumn doubleValue]];
            } else if ([attributes->objectClass isSubclassOfClass:[NSData class]]) {
                value = [resultSet dataForColumn:columnName];
            } else {
                value = [resultSet stringForColumn:columnName];
            }
            free(attributes);
		} @catch (NSException *ex) {
			if (error != NULL) {
				NSDictionary *userInfo = @{
                                           NSLocalizedDescriptionKey: NSLocalizedString(@"Invalid FMResultSet", nil),
                                           NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:NSLocalizedString(@"%1$@ could not be parsed because an invalid dictionary was provided for column \"%2$@\"", nil), modelClass, columnName],
                                           MTLFMDBAdapterThrownExceptionErrorKey: ex
                                           };
                
				*error = [NSError errorWithDomain:MTLFMDBAdapterErrorDomain code:MTLFMDBAdapterErrorInvalidFMResultSet userInfo:userInfo];
			}
            
			return nil;
		}
        
		if (value == nil) continue;
        
		@try {
			NSValueTransformer *transformer = [self FMDBTransformerForKey:propertyKey];
			if (transformer != nil) {
				// Map NSNull -> nil for the transformer, and then back for the
				// dictionary we're going to insert into.
				if ([value isEqual:NSNull.null]) value = nil;
				value = [transformer transformedValue:value] ?: NSNull.null;
			}
            
			dictionaryValue[propertyKey] = value;
		} @catch (NSException *ex) {
			NSLog(@"*** Caught exception %@ parsing column \"%@\" from: %@", ex, columnName, self.FMDBDictionary);
            
			// Fail fast in Debug builds.
#if DEBUG
			@throw ex;
#else
			if (error != NULL) {
				NSDictionary *userInfo = @{
                                           NSLocalizedDescriptionKey: ex.description,
                                           NSLocalizedFailureReasonErrorKey: ex.reason,
                                           MTLFMDBAdapterThrownExceptionErrorKey: ex
                                           };
                
				*error = [NSError errorWithDomain:MTLFMDBAdapterErrorDomain code:MTLFMDBAdapterErrorExceptionThrown userInfo:userInfo];
			}
            
			return nil;
#endif
		}
	}
    
	_model = [self.modelClass modelWithDictionary:dictionaryValue error:error];
	if (_model == nil) return nil;
    
	return self;
}


#pragma mark Serialization

- (NSDictionary *)FMDBDictionary {
	NSDictionary *dictionaryValue = self.model.dictionaryValue;
	NSMutableDictionary *FMDBDictionary = [[NSMutableDictionary alloc] initWithCapacity:dictionaryValue.count];
    
	[dictionaryValue enumerateKeysAndObjectsUsingBlock:^(NSString *propertyKey, id value, BOOL *stop) {
		NSString *columnName = [self FMDBColumnForPropertyKey:propertyKey];
		if (columnName == nil) return;
        
		NSValueTransformer *transformer = [self FMDBTransformerForKey:propertyKey];
		if ([transformer.class allowsReverseTransformation]) {
			// Map NSNull -> nil for the transformer, and then back for the
			// dictionaryValue we're going to insert into.
			if ([value isEqual:NSNull.null]) value = nil;
			value = [transformer reverseTransformedValue:value] ?: NSNull.null;
		}
        
		NSArray *keyPathComponents = [columnName componentsSeparatedByString:@"."];
        
		// Set up dictionaries at each step of the key path.
		id obj = FMDBDictionary;
		for (NSString *component in keyPathComponents) {
			if ([obj valueForKey:component] == nil) {
				// Insert an empty mutable dictionary at this spot so that we
				// can set the whole key path afterward.
				[obj setValue:[NSMutableDictionary dictionary] forKey:component];
			}
            
			obj = [obj valueForKey:component];
		}
        
		[FMDBDictionary setValue:value forKeyPath:columnName];
	}];
    
	return FMDBDictionary;
}

- (NSValueTransformer *)FMDBTransformerForKey:(NSString *)key {
	NSParameterAssert(key != nil);
    
	SEL selector = MTLSelectorWithKeyPattern(key, "FMDBTransformer");
	if ([self.modelClass respondsToSelector:selector]) {
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self.modelClass methodSignatureForSelector:selector]];
		invocation.target = self.modelClass;
		invocation.selector = selector;
		[invocation invoke];
        
		__unsafe_unretained id result = nil;
		[invocation getReturnValue:&result];
		return result;
	}
    
	if ([self.modelClass respondsToSelector:@selector(FMDBTransformerForKey:)]) {
		return [self.modelClass FMDBTransformerForKey:key];
	}
    
	return nil;
}

- (NSString *)FMDBColumnForPropertyKey:(NSString *)key {
	NSParameterAssert(key != nil);
    
	id columnName = self.FMDBColumnsByPropertyKey[key];
	if ([columnName isEqual:NSNull.null]) return nil;
    
	if (columnName == nil) {
		return key;
	} else {
		return columnName;
	}
}

+ (NSString *)propertyKeyForModel:(MTLModel<MTLFMDBSerializing> *)model column:(NSString *)column
{
    NSDictionary *columns = [model.class FMDBColumnsByPropertyKey];
    NSArray *allValues = [columns allValues];
    NSArray *allPropertyKeys = [columns allKeys];
    NSString *propertyKey = nil;
    NSIndexSet *idx = [allValues indexesOfObjectsPassingTest:^BOOL(NSString *obj, NSUInteger idx, BOOL *stop) {
        if (![obj isKindOfClass:NSNull.class] && ([obj caseInsensitiveCompare:column] == NSOrderedSame)) return YES;
        return NO;
    }];
    if (idx.count > 0 ) propertyKey = allPropertyKeys[idx.firstIndex];
    NSAssert(propertyKey != nil, @"Property key for column %@ is nil", column);
    return propertyKey;
}

+ (NSArray *)primaryKeysValues:(MTLModel<MTLFMDBSerializing> *)model {
    return @[@"rowid"];
}

+ (NSString *)createStatementForModel:(Class)modelClass
{
    NSAssert([modelClass isSubclassOfClass:[MTLModel class]], @"parameter class is not a subclass of MTLModel");
    NSAssert(![modelClass resolveClassMethod:@selector(FMDBColumnsByPropertyKey)], @"parameter class doesn't implement the FMDBColumnsByPropertyKey method");
    
    NSDictionary *columnsTypes = [MTLFMDBAdapter columnsTypeByPropertyKeyForModelClass:modelClass];
    
    NSMutableString *statement = [[NSMutableString alloc] initWithFormat:@"create table if not exists %@ (mtlfmdb_rowid integer primary key autoincrement",[modelClass FMDBTableName]];
    
    int count = 0;
    NSArray *columnNames = [MTLFMDBAdapter columnsNamesForModelClass:modelClass];
    
    for (NSString *keyPath in columnNames)
    {
        if (keyPath != nil && ![keyPath isEqual:[NSNull null]])
        {
            //non devo mettere la virgola neanche se tutti i restanti valori dell'array sono uguali a nsnull
            [statement appendFormat:@", %@ %@",keyPath, columnsTypes[keyPath]];
        }
        count++;
    }
    
    [statement appendString:@")"];
    
    return statement;
}

+ (NSString *)deleteStatementForModelClass:(Class)modelClass
{
    NSAssert([modelClass isSubclassOfClass:[MTLModel class]], @"parameter class is not a subclass of MTLModel");
    NSAssert(![modelClass resolveClassMethod:@selector(FMDBColumnsByPropertyKey)], @"parameter class doesn't implement the FMDBColumnsByPropertyKey method");
    return [NSString stringWithFormat:@"drop table if exists %@",[modelClass FMDBTableName]];;
}

+ (NSString *)insertStatementForModel:(MTLModel<MTLFMDBSerializing> *)model
{
    NSMutableArray *stats = [NSMutableArray array];
    NSMutableArray *qmarks = [NSMutableArray array];
    
    NSArray *columnNames = [MTLFMDBAdapter columnsNamesForModelClass:model.class];
    for (NSString *keyPath in columnNames)
    {
    	if (keyPath != nil && ![keyPath isEqual:[NSNull null]])
        {
            [stats addObject:keyPath];
            [qmarks addObject:[NSString stringWithFormat:@":%@",keyPath]];
        }
    }
    
    NSString *statement = [NSString stringWithFormat:@"insert into %@ (%@) values (%@)", [model.class FMDBTableName], [stats componentsJoinedByString:@", "], [qmarks componentsJoinedByString:@", "]];
    
    return statement;
}

+ (NSString *)updateStatementForModel:(MTLModel<MTLFMDBSerializing> *)model
{
    NSMutableArray *stats = [NSMutableArray array];
    NSArray *columnNames = [MTLFMDBAdapter columnsNamesForModelClass:model.class];
	for (NSString *keyPath in columnNames) {
        if (keyPath != nil && ![keyPath isEqual:[NSNull null]]) {
            NSString *s = [NSString stringWithFormat:@"%@ = :%@", keyPath, keyPath];
            [stats addObject:s];
        }
    }
    
    return [NSString stringWithFormat:@"update %@ set %@ where %@", [model.class FMDBTableName], [stats componentsJoinedByString:@", "], [self whereStatementForModel:model]];
}

+ (NSString *)deleteStatementForModel:(MTLModel<MTLFMDBSerializing> *)model
{
    NSParameterAssert([model.class conformsToProtocol:@protocol(MTLFMDBSerializing)]);
    
    return [NSString stringWithFormat:@"delete from %@ where %@", [model.class FMDBTableName], [self whereStatementForModel:model]];
}

+ (NSString *)whereStatementForModel:(MTLModel<MTLFMDBSerializing> *)model
{
    return @"mtlfmdb_rowid = :mtlfmdb_rowid";
}

+ (NSArray*) columnsNamesForModelClass:(Class)modelClass
{
    return [[MTLFMDBAdapter columnsNamesDictionaryForModelClass:modelClass] allValues];
}

+ (NSDictionary*) columnsNamesDictionaryForModelClass:(Class)modelClass
{
    NSAssert([modelClass isSubclassOfClass:[MTLModel class]], @"parameter class is not a subclass of MTLModel");
    NSAssert(![modelClass resolveClassMethod:@selector(FMDBColumnsByPropertyKey)], @"parameter class doesn't implement the FMDBColumnsByPropertyKey method");
    
    NSDictionary *columns = [modelClass FMDBColumnsByPropertyKey];
    NSSet *propertyKeys = [modelClass propertyKeys];
    NSArray *keys = [[propertyKeys allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableDictionary *columnsNamesDict = [[NSMutableDictionary alloc] initWithCapacity:keys.count];
    
    for (NSString *propertyKey in keys) {
        NSString *keyPath = columns[propertyKey];
        keyPath = keyPath ? : propertyKey;
        [columnsNamesDict setObject:keyPath forKey:propertyKey];
    }
    return [columnsNamesDict copy];
}

+ (NSDictionary*) columnsTypeByPropertyKeyForModelClass:(Class)modelClass
{
    NSParameterAssert([modelClass conformsToProtocol:@protocol(MTLFMDBSerializing)]);
 
    NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
    
    //prendo tutti i campi della classe passata
    [self enumeratePropertiesForClass:modelClass usingBlock:^(objc_property_t property, BOOL *stop) {
        mtl_propertyAttributes *attributes = mtl_copyPropertyAttributes(property);
        @onExit {
            free(attributes);
        };
        
        if (attributes->readonly && attributes->ivar == NULL) return;
        NSString *key = @(property_getName(property));
        
        NSString *propertyType = @"";
        if ([@(attributes->type) isEqualToString:@"i"]) {
            propertyType = @"integer";
        }else if ([@(attributes->type) isEqualToString:@"d"]) {
            propertyType = @"double";
        }else if ([@(attributes->type) isEqualToString:@"f"]) {
            propertyType = @"real";
        }else if ([@(attributes->type) isEqualToString:@"l"]) {
            propertyType = @"bigint";
        }else if ([@(attributes->type) isEqualToString:@"s"]) {
            propertyType = @"smallint";
        }else if ([@(attributes->type) isEqualToString:@"c"]) { //bool
            propertyType = @"boolean";
        }else{
            if(attributes->objectClass == [NSString class]){
                propertyType = @"text";
            }else if(attributes->objectClass == [NSDate class]){
                propertyType = @"int8";
            }else if(attributes->objectClass == [NSData class]){
                propertyType = @"blob";
            }else if(attributes->objectClass == [NSArray class]){
                //relazione uno a molti, non viene considerato
            }else{
                //se c'è un riferimento ad un altro oggetto che ha una tabella relativa inserisco un riferimento al suo id
                if (attributes->objectClass && [attributes->objectClass conformsToProtocol:@protocol(MTLFMDBSerializing)]) {
                    propertyType = @"int";
                }else if([modelClass resolveClassMethod:@selector(FMDBColumnsTypeByPropertyKey)]){
                    NSDictionary *columnTypes = [modelClass FMDBColumnsTypeByPropertyKey];
                    if (columnTypes[key] != nil) {
                        propertyType = columnTypes[key];
                    }
                }
            }
        }
        result[key] = propertyType;
    }];

    return [result copy];
}

#pragma mark - Private methods


//Metodo rubato ad MTLModel
+ (void)enumeratePropertiesForClass:(Class)class usingBlock:(void (^)(objc_property_t property, BOOL *stop))block {
    BOOL stop = NO;
    
    while (!stop && ![class isEqual:MTLModel.class]) {
        unsigned count = 0;
        objc_property_t *properties = class_copyPropertyList(class, &count);
        
        class = class.superclass;
        if (properties == NULL) continue;
        
        @onExit {
            free(properties);
        };
        
        for (unsigned i = 0; i < count; i++) {
            block(properties[i], &stop);
            if (stop) break;
        }
    }
}


@end
