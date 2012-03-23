/*
 * Fireside: yet another restful ORM mapper for cappuccino
 * ToDo:
 *	Store refactoring: FSAbstractStore with a Store for the Mojolicious example-backend.
 *  Check whether quoting is necessary in keys and vals (FSStore).
 *  catch write conflicts.
 *	TableView: looses changes when changing selection during edit: https://github.com/cappuccino/cappuccino/issues/1435
 *  invalidate relation caches when objects are added or removed from inside Fireside.
 *  make use of websockets to push backend changes to Fireside
 */

@import <Foundation/CPObject.j>

@implementation FSStore : CPObject 
{	CPString _baseURL @accessors(property=baseURL);
	unsigned _fetchLimit @accessors(property=fetchLimit);
}

-(id) initWithBaseURL:(CPString) someURL
{	self = [super init];
    if (self)
	{	_baseURL = someURL;
    }
    return self;
}
-(CPURLRequest) requestForWritingKey:(CPString) aKey ofObject: (id)obj toEntity:(FSEntity) someEntity
{	var request = [CPURLRequest requestWithURL: [self baseURL]+"/"+[someEntity name]+"/"+[obj valueForKey: [someEntity pk]]+"/"+aKey+'/'+[obj valueForKey: aKey]];
    [request setHTTPMethod:"PUT"];
	return request;
}

//<!> fixme: replace with something like writeChangesInObject
-(void) writeKey:(CPString) aKey ofObject: (id)obj
{	var request = [self requestForWritingKey: aKey ofObject: obj toEntity: [obj entity]];
	[CPURLConnection connectionWithRequest:request delegate: nil];
}

-(CPArray) fetchObjectsForURLRequest:(CPURLRequest) request inEntity: (FSEntity) someEntity
{	var data=[CPURLConnection sendSynchronousRequest: request returningResponse: nil];
	var j = JSON.parse( [data rawString]);
	var a=[CPMutableArray new];
	var i,l=j.length;
	for(i=0;i<l;i++)
	{	var pk=j[i][[someEntity pk]];
		var peek;
		if (peek=[someEntity _registeredObjectForPK: pk])	// enforce singleton pattern
		{	[a addObject:peek]; 
		} else
		{	var t=[[FSObject alloc] initWithEntity: someEntity];
			[t _setDataFromJSONObject: j[i]];
			[someEntity _registerObjectInPKCache: t];
			[a addObject:t];
		}
	}
	return a;
}
-(CPURLRequest) requestForFetchingAllObjectsInEntity:(FSEntity) someEntity
{	return [CPURLRequest requestWithURL: [self baseURL]+"/"+[someEntity name] ];
}
-(CPArray) fetchAllObjectsInEntity:(FSEntity) someEntity
{	return [self fetchObjectsForURLRequest: [self requestForFetchingAllObjectsInEntity: someEntity] inEntity:someEntity];
}

-(CPURLRequest) requestForFetchingObjectsWithKey: aKey equallingValue: (id) someval inEntity:(FSEntity) someEntity
{	var request = [CPURLRequest requestWithURL: [self baseURL]+"/"+[someEntity name]+"/"+aKey+"/"+someval];
	return request;
}

-(id) fetchObjectsWithKey: aKey equallingValue: (id) someval inEntity:(FSEntity) someEntity
{	if( aKey == [someEntity pk] ) 
	{	var peek;
		if(peek=[someEntity _registeredObjectForPK: someval]) return [CPArray arrayWithObject: peek];
	}

	var request =[self requestForFetchingObjectsWithKey: aKey equallingValue: someval inEntity: someEntity];
	return [self fetchObjectsForURLRequest: request inEntity: someEntity];
}

@end

FSRelationshipTypeToOne=0;
FSRelationshipTypeToMany=1;

@implementation FSRelationship : CPObject 
{	CPString _name @accessors(property=name);
	FSEntity _target @accessors(property=target);
	CPString _bindingColumn @accessors(property=bindingColumn);
	CPString _targetColumn @accessors(setter=setTargetColumn:);
	CPString _type @accessors(property=type);
	var _target_cache;
}
-(id) initWithName:(CPString) aName andTargetEntity:(FSEntity) anEntity
{	self = [super init];
    if (self)
	{	_target = anEntity;
		_name = aName;
		_type= FSRelationshipTypeToOne;
    }
    return self;

}
-(id) init
{	return [self initWithName: nil andTargetEntity: nil];
}
-(CPString) targetColumn
{	if(_targetColumn && _targetColumn.length) return _targetColumn;
	return [_target pk];
}
-(CPArray) fetchObjectsForKey:(id) targetPK
{	if(!targetPK) return nil;
	var peek;
	if(!_target_cache) _target_cache=[];
	if(peek=_target_cache[targetPK]) return peek;
	var res= [[_target store] fetchObjectsWithKey: [self targetColumn] equallingValue: targetPK inEntity: _target];
	_target_cache[targetPK]=res;
	return res;
}

-(void) invalidateCache
{	_target_cache=[];
}
@end

@implementation FSEntity : CPObject 
{	CPString _name @accessors(property=name);
	CPString _pk @accessors(property=pk);
	CPSet _columns @accessors(property=columns);
	CPSet _relations;
	FSStore	_store @accessors(property=store);
	CPMutableArray _pkcache;
}
-(id) initWithName:(CPString) aName andStore:(FSStore) someStore
{	self = [super init];
    if (self)
	{	_store = someStore;
		_name = aName;
    }
    return self;
}
-(id) init
{	return [self initWithName: nil andStore: nil];
}

-(FSRelationship) relationOfName:(CPString) aName
{	var rels=[_relations allObjects];
	var i,l=rels.length;
	for(i=0;i<l;i++)
	{	var r=rels[i];
		if([r name]==aName) return r;
	}
	return nil;
}
-(CPArray) relationships
{	return [_relations allObjects];
}

-(void) addRelationship:(FSRelationship) someRel
{	if(!_relations) _relations=[CPSet setWithObject:someRel];
	else [_relations addObject: someRel];
}

-(CPArray) allObjects
{
	return [_store fetchAllObjectsInEntity: self];
}

-(void) _registerObjectInPKCache:(id) someObj
{	if(!_pkcache) _pkcache=[CPMutableArray new];
	_pkcache[[someObj valueForKey:_pk]]=someObj;
}
-(void) _registeredObjectForPK:(id) somePK
{	if(!_pkcache) return nil;
	return _pkcache[somePK];
}
-(void) invalidateRelationshipCaches
{	[_relations makeObjectsPerformSelector:@selector(invalidateCache)];
}

@end

@implementation FSObject : CPObject 
{	CPMutableDictionary _data;
	CPMutableDictionary _changes;
	FSEntity _entity @accessors(property=entity);
}

-(id) initWithEntity:(id) anEntity
{	self = [super init];
    if (self)
	{	_entity=anEntity;
    }
    return self;
}

- (void)_setDataFromJSONObject:(id) o
{	_data = [CPMutableDictionary dictionary];
	var cols=[[_entity columns] allObjects];
	var i,l=cols.length;
    for(i=0; i<l; i++)
    {	var propName = cols[i];
		[_data setObject: o[propName] forKey:propName];
    }
}

- (id)description
{	return [_data description];
}

-(int) typeOfKey:(CPString)aKey
{	if( [[_entity columns] containsObject: aKey]) return 0;
	if( [_entity relationOfName: aKey]) return 1;
	return -1;
}

- (id)valueForKey:(CPString)aKey
{	var type= [self typeOfKey: aKey];

	if(type == 0)
	{	if(!_data)		// <!>fixme: implement lazy (batch-) fetching here
		{
		}
	
		var o=[_changes objectForKey: aKey];
		if (o) return o;
		return [_data objectForKey: aKey];
	} else if(type == 1)	// to one relation: aKey is accessed
	{	var rel=[_entity relationOfName: aKey];
		var bindingColumn=[rel bindingColumn];
		if(!bindingColumn) bindingColumn=[_entity pk];

		var results=[rel fetchObjectsForKey: [self valueForKey: bindingColumn] ];

		return [rel type]== FSRelationshipTypeToMany? results: ((results && results.length)? [results objectAtIndex: 0] : nil) ;
	} else [CPException raise:CPInvalidArgumentException reason:@"Key "+aKey+" is not a column in entity "+[_entity name]];
	
}

- (void)setValue: someval forKey:(CPString)aKey
{	var type= [self typeOfKey: aKey];
	if(type == 0)
	{	if(!_changes) _changes = [CPMutableDictionary dictionary];
		[self willChangeValueForKey:aKey];
		[_changes setObject: someval forKey: aKey];
		[self didChangeValueForKey:aKey];
		[[_entity store] writeKey: aKey ofObject:self];
	} else if(type == 1)
	{	//<!> fixme: provide meaningful implementation for "Relation: "+aKey+" is written at"
	} else [CPException raise:CPInvalidArgumentException reason:@"Key "+aKey+" is not a column"];
	
}

@end