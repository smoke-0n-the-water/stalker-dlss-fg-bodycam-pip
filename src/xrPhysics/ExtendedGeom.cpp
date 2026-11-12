#include	"stdafx.h"
#include	"extendedgeom.h"
#include	"dcylinder/dcylinder.h"

bool IsCyliderContact(const dContact& c)
{
	int geomClass = -1;
	if (dGeomGetBody(c.geom.g1))
	{
		geomClass = dGeomGetClass(retrieveGeom(c.geom.g1));
	}
	else
	{
		geomClass = dGeomGetClass(retrieveGeom(c.geom.g2));
	}

	//is_cyl= (geomClass==dCylinderClassUser);
	return (geomClass == dCylinderClassUser);
}

PHRefObjectResolverFun* g_ph_ref_object_resolver = nullptr;

IPhysicsShellHolder* PHLiveRefObject(const dxGeomUserData* ud)
{
	if (!ud || !ud->ph_ref_object)
		return nullptr;
	// No id recorded (not a level object) or no resolver: nothing to check against.
	if (ud->ph_ref_object_id == u16(-1) || !g_ph_ref_object_resolver)
		return ud->ph_ref_object;
	if (g_ph_ref_object_resolver(ud->ph_ref_object_id) == ud->ph_ref_object)
		return ud->ph_ref_object;
	static u16 reported = u16(-1);
	if (reported != ud->ph_ref_object_id)
	{
		reported = ud->ph_ref_object_id;
		Msg("! [Physics] contact with a shell whose owner (id %u) no longer exists; ignored", u32(ud->ph_ref_object_id));
	}
	return nullptr;
}

//dxGeomUserData* PHGeomGetUserData( dxGeom* geom )
//{
//	return dGeomGetUserData(geom);
//}

dxGeomUserData* PHRetrieveGeomUserData(dGeomID geom)
{
	return retrieveGeomUserData(geom);
}

void get_user_data(dxGeomUserData* & gd1, dxGeomUserData* & gd2, bool bo1, const dContactGeom& geom)
{
	if (bo1)
	{
		gd1 = retrieveGeomUserData(geom.g1);
		gd2 = retrieveGeomUserData(geom.g2);
	}
	else
	{
		gd2 = retrieveGeomUserData(geom.g1);
		gd1 = retrieveGeomUserData(geom.g2);
	}
}

//  bool dGeomUserDataHasCallback(dxGeom* geom,ObjectContactCallbackFun	*obj_callback)
//{
//	geom=retrieveGeom(geom);
//	if(geom&&dGeomGetUserData(geom)&&(dGeomGetUserData(geom))->object_callbacks)
//				return (dGeomGetUserData(geom))->object_callbacks->HasCallback(obj_callback);
//	else return false;
//}
